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
# PURPOSE: this strategy should be cross-platform and maintain SELinux contexts
#          and windows ACL inheritance, but it uses cp and is both slower and is
#          not atomic and may result in a corrupted destination file in low
#          disk or power outage situations.
#

class Chef
  class Provider
    class File
      class Deploy
        class CP
          def create(file)
            FileUtils.touch(file)
          end

          def deploy(src, dst)
            FileUtils.cp(src, dst)
          end
        end
      end
    end
  end
end
