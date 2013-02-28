#
# Author:: Lamont Granquist (<lamont@opscode.com>)
# Copyright:: Copyright (c) 2013 Opscode, Inc.
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

require 'chef/mixin/checksum'
require 'chef/mixin/backupable_file_resource'
require 'chef/mixin/diffable_file_resource'

class Chef
  class Provider
    class File
      class ContentHelper
        include Chef::Mixin::Checksum
        include Chef::Mixin::DiffableFileResource
        include Chef::Mixin::BackupableFileResource

        attr_accessor :run_context

        def initialize(provider, content_object, deployment_strategy, new_resource, current_resource, run_context)
          @provider = provider
          @content_object = content_object
          @deployment_strategy = deployment_strategy
          @new_resource = new_resource
          @current_resource = current_resource
          @run_context = run_context
        end

        def do_create_file
          unless ::File.exists?(@new_resource.path)
            description = "create new file #{@new_resource.path}"
            @provider.converge_by(description) do
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
            description = [ "update content in file #{@new_resource.path} from #{short_cksum(@current_resource.checksum)} to #{short_cksum(checksum)}" ]
            description << diff(tempfile.path)
            @provider.converge_by(description) do
              # XXX: since we now always create the file before deploying content, we will always backup a file here
              backup @new_resource.path if ::File.exists?(@new_resource.path)
              @deployment_strategy.deploy(tempfile.path, @new_resource.path)
              Chef::Log.info("#{@new_resource} updated file contents #{@new_resource.path}")
            end
          end
          # unlink necessary to clean up in why-run mode
          tempfile.unlink
        end

        private

        def contents_changed?
          checksum != @current_resource.checksum
        end

        def tempfile
          @content_object.tempfile
        end

        def checksum
          Chef::Digester.checksum_for_file(tempfile.path)
        end

        def whyrun_mode?
          Chef::Config[:why_run]
        end

        def short_cksum(checksum)
          return "none" if checksum.nil?
          checksum.slice(0,6)
        end
      end
    end
  end
end

