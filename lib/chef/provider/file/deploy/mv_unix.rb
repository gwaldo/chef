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

#
# PURPOSE: this strategy is atomic and preserves modes, but will not restore SELinux contexts
#

class Chef
  class Provider
    class File
      class Deploy
        class MvUnix
          def create(file)
            FileUtils.touch(file)
          end

          def deploy(src, dst)
            if ::File.dirname(src) != ::File.dirname(dst)
              # internal warning - in a Windows/SElinux/ACLs world its better to write
              # a tempfile to your destination directory and then rename it
              Chef::Log.debug("moving tempfile across different directories -- this may break permissions")
            end

            # we are only responsible for content so restore the dst files perms
            mode = ::File.stat(dst).mode & 07777
            uid  = ::File.stat(dst).uid
            gid  = ::File.stat(dst).gid
            Chef::Log.debug("saved mode = #{mode.to_s(8)}, uid = #{uid}, gid = #{gid} from #{dst}")
            Chef::Log.debug("moving temporary file #{src} into place at #{dst}")
            FileUtils.mv(src, dst)
            ::File.chmod(mode, dst)
            ::File.chown(uid, gid, dst)
            Chef::Log.debug("restored mode = #{mode.to_s(8)}, uid = #{uid}, gid = #{gid} to #{dst}")
          end
        end
      end
    end
  end
end
