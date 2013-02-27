#
# Author:: Jesse Campbell (<hikeit@gmail.com>)
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

require 'rest_client'
require 'uri'
require 'tempfile'
require 'chef/provider/file/content'

class Chef
  class Provider
    class File
      class Content
        class RemoteFile < Chef::Provider::File::Content

          private

          def file_for_provider
            Chef::Log.debug("#{@new_resource} checking for changes")

            if current_resource_matches_target_checksum?
              Chef::Log.debug("#{@new_resource} checksum matches target checksum (#{@new_resource.checksum}) - not updating")
            else
              sources = @new_resource.source
              raw_file, raw_file_source = try_multiple_sources(sources)
              # FIXME: need to expose raw_file_source as a method
              # https://github.com/opscode/chef/pull/602/files#L0R48
            end
            raw_file
          end

          def current_resource_matches_target_checksum?
            @new_resource.checksum && @current_resource.checksum && @current_resource.checksum =~ /^#{Regexp.escape(@new_resource.checksum)}/
          end

          # Given an array of source uris, iterate through them until one does not fail
          def try_multiple_sources(sources)
            sources = sources.dup
            source = sources.shift
            begin
              uri = URI.parse(source)
              raw_file = grab_file_from_uri(uri)
            rescue ArgumentError => e
              raise e
            rescue => e
              if e.is_a?(RestClient::Exception)
                error = "Request returned #{e.message}"
              else
                error = e.to_s
              end
              Chef::Log.debug("#{@new_resource} cannot be downloaded from #{source}: #{error}")
              if source = sources.shift
                Chef::Log.debug("#{@new_resource} trying to download from another mirror")
                retry
              else
                raise e
              end
            end
            if uri.userinfo
              uri.password = "********"
            end
            return raw_file, uri.to_s
          end

          # Given a source uri, return a Tempfile, or a File that acts like a Tempfile (close! method)
          def grab_file_from_uri(uri)
            if URI::HTTP === uri
              #HTTP or HTTPS
              raw_file = RestClient::Request.execute(:method => :get, :url => uri.to_s, :raw_response => true).file
            elsif URI::FTP === uri
              #FTP
              raw_file = Chef::Provider::RemoteFile::FTP::fetch(uri, @new_resource.ftp_active_mode)
            elsif uri.scheme == "file"
              #local/network file
              raw_file = ::File.new(uri.path, "r")
              def raw_file.close!
                self.close
              end
            else
              raise ArgumentError, "Invalid uri. Only http(s), ftp, and file are currently supported"
            end
            raw_file
          end

        end
      end
    end
  end
end
