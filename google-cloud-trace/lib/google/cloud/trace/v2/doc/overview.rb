# Copyright 2017 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

module Google
  module Cloud
    # rubocop:disable LineLength

    ##
    # # Ruby Client for Stackdriver Trace API ([Beta](https://github.com/GoogleCloudPlatform/google-cloud-ruby#versioning))
    #
    # [Stackdriver Trace API][Product Documentation]:
    # Sends application trace data to Stackdriver Trace for viewing. Trace data is
    # collected for all App Engine applications by default. Trace data from other
    # applications can be provided using this API.
    # - [Product Documentation][]
    #
    # ## Quick Start
    # In order to use this library, you first need to go through the following
    # steps:
    #
    # 1. [Select or create a Cloud Platform project.](https://console.cloud.google.com/project)
    # 2. [Enable billing for your project.](https://cloud.google.com/billing/docs/how-to/modify-project#enable_billing_for_a_project)
    # 3. [Enable the Stackdriver Trace API.](https://console.cloud.google.com/apis/api/trace)
    # 4. [Setup Authentication.](https://googlecloudplatform.github.io/google-cloud-ruby/#/docs/google-cloud/master/guides/authentication)
    #
    # ### Installation
    # ```
    # $ gem install google-cloud-trace
    # ```
    #
    # ### Preview
    # #### TraceServiceClient
    # ```rb
    # require "google/cloud/trace"
    #
    # trace_service_client = Google::Cloud::Trace.new
    # formatted_name = Google::Cloud::Trace::V2::TraceServiceClient.project_path(project_id)
    # spans = []
    # trace_service_client.batch_write_spans(formatted_name, spans)
    # ```
    #
    # ### Next Steps
    # - Read the [Stackdriver Trace API Product documentation][Product Documentation]
    #   to learn more about the product and see How-to Guides.
    # - View this [repository's main README](https://github.com/GoogleCloudPlatform/google-cloud-ruby/blob/master/README.md)
    #   to see the full list of Cloud APIs that we cover.
    #
    # [Product Documentation]: https://cloud.google.com/trace
    #
    #
    module Trace
      module V2
      end
    end
  end
end
