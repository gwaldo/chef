#
# Author:: Adam Jacob (<adam@opscode.com>)
# Author:: Lamont Granquist (<lamont@opscode.com>)
# Copyright:: Copyright (c) 2008-2013 Opscode, Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'chef/config'
require 'chef/log'
require 'chef/resource/file'
require 'chef/provider'
require 'etc'
require 'fileutils'
require 'chef/scan_access_control'
require 'chef/mixin/checksum'
require 'chef/mixin/backupable_file_resource'
require 'chef/mixin/diffable_file_resource'

# The Tao of File Providers:
#  - the content provider must always return a tempfile that we can delete/mv
#  - do_create_file shall always create the file first and obey umask when perms are not specified
#  - do_contents_changes may assume the destination file exists (simplifies exception checking,
#    and always gives us something to diff against)
#  - do_contents_changes must restore the perms to the dest file and not obliterate them with
#    random tempfile permissions
#  - do_acl_changes may assume perms were not modified between lcr and when it runs (although the
#    file may have been created)

class Chef
  class Provider
    class File < Chef::Provider
      include Chef::Mixin::EnforceOwnershipAndPermissions
      include Chef::Mixin::Checksum
      include Chef::Mixin::BackupableFileResource
      include Chef::Mixin::DiffableFileResource

      def initialize(new_resource, run_context)
        @content_class ||= Chef::Provider::File::Content::File
        @deployment_strategy = new_resource.deployment_strategy.new() if new_resource.respond_to?(:deployment_strategy)
        super
      end

      def whyrun_supported?
        true
      end

      def content_object
        # object created lazily after current resource is loaded
        @content_object ||= @content_class.new(@new_resource, @current_resource, @run_context)
      end

      def load_current_resource
        # Let children resources override constructing the @current_resource
        @current_resource ||= Chef::Resource::File.new(@new_resource.name)
        @new_resource.path.gsub!(/\\/, "/") # for Windows
        @current_resource.path(@new_resource.path)
        load_resource_attributes_from_file(@current_resource)
        @current_resource
      end

      def define_resource_requirements
        # Make sure the parent directory exists, otherwise fail.  For why-run assume it would have been created.
        requirements.assert(:create, :create_if_missing, :touch) do |a|
          parent_directory = ::File.dirname(@new_resource.path)
          a.assertion { ::File.directory?(parent_directory) }
          a.failure_message(Chef::Exceptions::EnclosingDirectoryDoesNotExist, "Parent directory #{parent_directory} does not exist.")
          a.whyrun("Assuming directory #{parent_directory} would have been created")
        end

        # Make sure the file is deletable if it exists, otherwise fail.
        if ::File.exists?(@new_resource.path)
          requirements.assert(:delete) do |a|
            a.assertion { ::File.writable?(@new_resource.path) }
            a.failure_message(Chef::Exceptions::InsufficientPermissions,"File #{@new_resource.path} exists but is not writable so it cannot be deleted")
          end
        end
      end

      def do_create_file
        unless ::File.exists?(@new_resource.path)
          description = "create new file #{@new_resource.path}"
          converge_by(description) do
            @deployment_strategy.create(@new_resource.path)
            Chef::Log.info("#{@new_resource} created file #{@new_resource.path}")
          end
        end
      end

      def do_contents_changes
        # a nil tempfile is okay, means the resource has no content or no new content
        return if tempfile.nil?
        # but a tempfile that has no path or doesn't exist should not happen
        if tempfile.path.nil? || !::File.exists?(tempfile.path)
          raise "chef-client is confused, trying to deploy a file that has no path or does not exist..."
        end
        if contents_changed?
          description = [ "update content in file #{@new_resource.path} from #{short_cksum(@current_resource.checksum)} to #{short_cksum(checksum(tempfile.path))}" ]
          description << diff(tempfile.path)
          converge_by(description) do
            # XXX: since we now always create the file before deploying content, we will always backup a file here
            backup @new_resource.path if ::File.exists?(@new_resource.path)
            @deployment_strategy.deploy(tempfile.path, @new_resource.path)
            Chef::Log.info("#{@new_resource} updated file contents #{@new_resource.path}")
          end
        end
        # unlink necessary to clean up in why-run mode
        tempfile.unlink
      end

      def do_acl_changes
        if access_controls.requires_changes?
          converge_by(access_controls.describe_changes) do
            access_controls.set_all
          end
        end
      end

      def action_create
        do_create_file
        do_contents_changes
        do_acl_changes
        load_resource_attributes_from_file(@new_resource)
      end

      def action_create_if_missing
        if ::File.exists?(@new_resource.path)
          Chef::Log.debug("#{@new_resource} exists at #{@new_resource.path} taking no action.")
        else
          action_create
        end
      end

      def action_delete
        if ::File.exists?(@new_resource.path)
          converge_by("delete file #{@new_resource.path}") do
            backup unless ::File.symlink?(@new_resource.path)
            ::File.delete(@new_resource.path)
            Chef::Log.info("#{@new_resource} deleted file at #{@new_resource.path}")
          end
        end
      end

      def action_touch
        action_create
        converge_by("update utime on file #{@new_resource.path}") do
          time = Time.now
          ::File.utime(time, time, @new_resource.path)
          Chef::Log.info("#{@new_resource} updated atime and mtime to #{time}")
        end
      end

      private

      def contents_changed?
        checksum(tempfile.path) != @current_resource.checksum
      end

      def tempfile
        content_object.tempfile
      end

#      def checksum
#        Chef::Digester.checksum_for_file(tempfile.path)
#      end

      def whyrun_mode?
        Chef::Config[:why_run]
      end

      def short_cksum(checksum)
        return "none" if checksum.nil?
        checksum.slice(0,6)
      end

      # if you are using a tempfile before creating, you must
      # override the default with the tempfile, since the
      # file at @new_resource.path will not be updated on converge
      def load_resource_attributes_from_file(resource)
        if resource.respond_to?(:checksum)
          if ::File.exists?(resource.path) && !::File.directory?(resource.path)
            if @action != :create_if_missing # XXX: don't we break current_resource semantics by skipping this?
              resource.checksum(checksum(resource.path))
            end
          end
        end

        if Chef::Platform.windows?
          # TODO: To work around CHEF-3554, add support for Windows
          # equivalent, or implicit resource reporting won't work for
          # Windows.
          return
        end

        acl_scanner = ScanAccessControl.new(@new_resource, resource)
        acl_scanner.set_all!
      end

    end
  end
end

