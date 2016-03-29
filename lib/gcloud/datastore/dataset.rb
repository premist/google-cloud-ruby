# Copyright 2014 Google Inc. All rights reserved.
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


require "gcloud/gce"
require "gcloud/datastore/grpc_utils"
require "gcloud/datastore/credentials"
require "gcloud/datastore/service"
require "gcloud/datastore/entity"
require "gcloud/datastore/key"
require "gcloud/datastore/query"
require "gcloud/datastore/dataset/lookup_results"
require "gcloud/datastore/dataset/query_results"

module Gcloud
  module Datastore
    ##
    # # Dataset
    #
    # Dataset is the data saved in a project's Datastore.
    # Dataset is analogous to a database in relational database world.
    #
    # Gcloud::Datastore::Dataset is the main object for interacting with
    # Google Datastore. {Gcloud::Datastore::Entity} objects are created,
    # read, updated, and deleted by Gcloud::Datastore::Dataset.
    #
    # See {Gcloud#datastore}
    #
    # @example
    #   require "gcloud"
    #
    #   gcloud = Gcloud.new
    #   dataset = gcloud.datastore
    #
    #   query = dataset.query("Task").
    #     where("completed", "=", true)
    #
    #   tasks = dataset.run query
    #
    class Dataset
      ##
      # @private The gRPC Service object.
      attr_accessor :service

      ##
      # @private Creates a new Dataset instance.
      #
      # See {Gcloud#datastore}
      def initialize project, credentials
        project = project.to_s # Always cast to a string
        fail ArgumentError, "project is missing" if project.empty?
        @service = Service.new project, credentials
      end

      ##
      # The Datastore project connected to.
      #
      # @example
      #   require "gcloud"
      #
      #   gcloud = Gcloud.new "my-todo-project",
      #                       "/path/to/keyfile.json"
      #
      #   dataset = gcloud.datastore
      #   dataset.project #=> "my-todo-project"
      #
      def project
        service.project
      end

      ##
      # @private Default project.
      def self.default_project
        ENV["DATASTORE_DATASET"] ||
          ENV["DATASTORE_PROJECT"] ||
          ENV["GCLOUD_PROJECT"] ||
          ENV["GOOGLE_CLOUD_PROJECT"] ||
          Gcloud::GCE.project_id
      end

      ##
      # Generate IDs for a Key before creating an entity.
      #
      # @param [Key] incomplete_key A Key without `id` or `name` set.
      # @param [String] count The number of new key IDs to create.
      #
      # @return [Array<Gcloud::Datastore::Key>]
      #
      # @example
      #   empty_key = dataset.key "Task"
      #   task_keys = dataset.allocate_ids empty_key, 5
      #
      def allocate_ids incomplete_key, count = 1
        if incomplete_key.complete?
          fail Gcloud::Datastore::Error, "An incomplete key must be provided."
        end

        ensure_service!
        incomplete_keys = count.times.map { incomplete_key.to_grpc }
        allocate_res = service.allocate_ids(*incomplete_keys)
        allocate_res.keys.map { |key| Key.from_grpc key }
      end

      ##
      # Persist one or more entities to the Datastore.
      #
      # @param [Entity] entities One or more entity objects to be saved without
      #   `id` or `name` set.
      #
      # @return [Array<Gcloud::Datastore::Entity>]
      #
      # @example
      #   dataset.save task1, task2
      #
      def save *entities
        ensure_service!
        mutations = create_save_mutations entities
        commit_res = service.commit(mutations)
        returned_keys = commit_res.mutation_results.map(&:key)
        update_incomplete_keys_on_saved_entities returned_keys
        entities
      end

      ##
      # Retrieve an entity by providing key information.
      #
      # @param [Key, String] key_or_kind A Key object or `kind` string value.
      # @param [Integer, String, nil] id_or_name The Key's `id` or `name` value
      #   if a `kind` was provided in the first parameter.
      #
      # @return [Gcloud::Datastore::Entity, nil]
      #
      # @example Finding an entity with a key:
      #   key = dataset.key "Task", 123456
      #   task = dataset.find key
      #
      # @example Finding an entity with a `kind` and `id`/`name`:
      #   task = dataset.find "Task", 123456
      #
      def find key_or_kind, id_or_name = nil
        key = key_or_kind
        unless key.is_a? Gcloud::Datastore::Key
          key = Key.new key_or_kind, id_or_name
        end
        find_all(key).first
      end
      alias_method :get, :find

      ##
      # Retrieve the entities for the provided keys.
      #
      # @param [Key] keys One or more Key objects to find records for.
      #
      # @return [Gcloud::Datastore::Dataset::LookupResults]
      #
      # @example
      #   gcloud = Gcloud.new
      #   dataset = gcloud.datastore
      #   key1 = dataset.key "Task", 123456
      #   key2 = dataset.key "Task", 987654
      #   tasks = dataset.find_all key1, key2
      #
      def find_all *keys
        ensure_service!
        lookup_res = service.lookup(*keys.map(&:to_grpc))
        entities = to_gcloud_entities lookup_res.found
        deferred = to_gcloud_keys lookup_res.deferred
        missing  = to_gcloud_entities lookup_res.missing
        LookupResults.new entities, deferred, missing
      end
      alias_method :lookup, :find_all

      ##
      # Remove entities from the Datastore.
      #
      # @param [Entity, Key] entities_or_keys One or more Entity or Key objects
      #   to remove.
      #
      # @return [Boolean] Returns `true` if successful
      #
      # @example
      #   gcloud = Gcloud.new
      #   dataset = gcloud.datastore
      #   dataset.delete entity1, entity2
      #
      def delete *entities_or_keys
        mutations = create_delete_mutations entities_or_keys

        ensure_service!
        service.commit mutations
        true
      end

      ##
      # Retrieve entities specified by a Query.
      #
      # @param [Query] query The Query object with the search criteria.
      # @param [String] namespace The namespace the query is to run within.
      #
      # @return [Gcloud::Datastore::Dataset::QueryResults]
      #
      # @example
      #   query = dataset.query("Task").
      #     where("completed", "=", true)
      #   tasks = dataset.run query
      #
      # @example Run the query within a namespace with the `namespace` option:
      #   query = Gcloud::Datastore::Query.new.kind("Task").
      #     where("completed", "=", true)
      #   tasks = dataset.run query, namespace: "ns~todo-project"
      #
      def run query, namespace: nil
        ensure_service!
        query_res = service.run_query query.to_grpc, namespace
        entities = to_gcloud_entities query_res.batch.entity_results
        cursor = GRPCUtils.encode_bytes query_res.batch.end_cursor
        more_results = query_res.batch.more_results
        QueryResults.new entities, cursor, more_results
      end
      alias_method :run_query, :run

      ##
      # Creates a Datastore Transaction.
      #
      # @yield [tx] a block yielding a new transaction
      # @yieldparam [Transaction] tx the transaction object
      #
      # @example Runs the given block in a database transaction:
      #   require "gcloud"
      #
      #   gcloud = Gcloud.new
      #   dataset = gcloud.datastore
      #
      #   user = dataset.entity "User", "heidi" do |u|
      #     u["name"] = "Heidi Henderson"
      #     u["email"] = "heidi@example.net"
      #   end
      #
      #   dataset.transaction do |tx|
      #     if tx.find(user.key).nil?
      #       tx.save user
      #     end
      #   end
      #
      # @example If no block is given, a Transaction object is returned:
      #   require "gcloud"
      #
      #   gcloud = Gcloud.new
      #   dataset = gcloud.datastore
      #
      #   user = dataset.entity "User", "heidi" do |u|
      #     u["name"] = "Heidi Henderson"
      #     u["email"] = "heidi@example.net"
      #   end
      #
      #   tx = dataset.transaction
      #   begin
      #     if tx.find(user.key).nil?
      #       tx.save user
      #     end
      #     tx.commit
      #   rescue
      #     tx.rollback
      #   end
      #
      def transaction
        tx = Transaction.new service
        return tx unless block_given?

        begin
          yield tx
          tx.commit
        rescue => e
          tx.rollback
          raise TransactionError.new("Transaction failed to commit.", e)
        end
      end

      ##
      # Create a new Query instance. This is a convenience method to make the
      # creation of Query objects easier.
      #
      # @param [String] kinds The kind of entities to query. This is optional.
      #
      # @return [Gcloud::Datastore::Query]
      #
      # @example
      #   query = dataset.query("Task").
      #     where("completed", "=", true)
      #   tasks = dataset.run query
      #
      # @example The previous example is equivalent to:
      #   query = Gcloud::Datastore::Query.new.
      #     kind("Task").
      #     where("completed", "=", true)
      #   tasks = dataset.run query
      #
      def query *kinds
        query = Query.new
        query.kind(*kinds) unless kinds.empty?
        query
      end

      ##
      # Create a new Key instance. This is a convenience method to make the
      # creation of Key objects easier.
      #
      # @param [String] kind The kind of the Key. This is optional.
      # @param [Integer, String] id_or_name The id or name of the Key. This is
      #   optional.
      #
      # @return [Gcloud::Datastore::Key]
      #
      # @example
      #   key = dataset.key "User", "heidi@example.com"
      #
      # @example The previous example is equivalent to:
      #   key = Gcloud::Datastore::Key.new "User", "heidi@example.com"
      #
      def key kind = nil, id_or_name = nil
        Key.new kind, id_or_name
      end

      ##
      # Create a new empty Entity instance. This is a convenience method to make
      # the creation of Entity objects easier.
      #
      # @param [Key, String, nil] key_or_kind A Key object or `kind` string
      #   value. This is optional.
      # @param [Integer, String, nil] id_or_name The Key's `id` or `name` value
      #   if a `kind` was provided in the first parameter.
      # @yield [entity] a block yielding a new entity
      # @yieldparam [Entity] entity the newly created entity object
      #
      # @return [Gcloud::Datastore::Entity]
      #
      # @example
      #   entity = dataset.entity
      #
      # @example The previous example is equivalent to:
      #   entity = Gcloud::Datastore::Entity.new
      #
      # @example The key can also be passed in as an object:
      #   key = dataset.key "User", "heidi@example.com"
      #   entity = dataset.entity key
      #
      # @example Or the key values can be passed in as parameters:
      #   entity = dataset.entity "User", "heidi@example.com"
      #
      # @example The previous example is equivalent to:
      #   key = Gcloud::Datastore::Key.new "User", "heidi@example.com"
      #   entity = Gcloud::Datastore::Entity.new
      #   entity.key = key
      #
      # @example The newly created entity can also be configured using a block:
      #   user = dataset.entity "User", "heidi@example.com" do |u|
      #     u["name"] = "Heidi Henderson"
      #  end
      #
      # @example The previous example is equivalent to:
      #   key = Gcloud::Datastore::Key.new "User", "heidi@example.com"
      #   entity = Gcloud::Datastore::Entity.new
      #   entity.key = key
      #   entity["name"] = "Heidi Henderson"
      #
      def entity key_or_kind = nil, id_or_name = nil
        entity = Entity.new

        # Set the key
        key = key_or_kind
        unless key.is_a? Gcloud::Datastore::Key
          key = Key.new key_or_kind, id_or_name
        end
        entity.key = key

        yield entity if block_given?

        entity
      end

      protected

      ##
      # @private Raise an error unless an active connection to the service is
      # available.
      def ensure_service!
        fail "Must have active connection to service" unless service
      end

      ##
      # Convenince method to convert GRPC entities to Gcloud entities.
      def to_gcloud_entities grpc_entity_results
        # Entities are nested in an object.
        Array(grpc_entity_results).map do |result|
          # TODO: Make this return an EntityResult with cursor...
          Entity.from_grpc result.entity
        end
      end

      ##
      # Convenince method to convert GRPC keys to Gcloud keys.
      def to_gcloud_keys grpc_keys
        # Keys are not nested in an object like entities are.
        Array(grpc_keys).map { |key| Key.from_grpc key }
      end

      ##
      # @private Save a key to be given an ID when comitted.
      def auto_id_register entity
        @_auto_id_entities ||= []
        @_auto_id_entities << entity
      end

      ##
      # @private Update saved keys with new IDs post-commit.
      def update_incomplete_keys_on_saved_entities keys
        @_auto_id_entities ||= []
        Array(keys).each_with_index do |key, index|
          entity = @_auto_id_entities[index]
          entity.key = Key.from_grpc key
        end
        @_auto_id_entities = []
      end

      ##
      # @private Convert entities to Mutations, and register entity to be
      # updated with a completed key if needed.
      def create_save_mutations entities
        mutations = []
        entities.each do |entity|
          auto_id_register entity if entity.key.incomplete?
          mutations << Google::Datastore::V1beta3::Mutation.new(
            upsert: entity.to_grpc)
        end
        mutations
      end

      ##
      # @private Convert entities or keys to Mutations.
      def create_delete_mutations entities_or_keys
        entities_or_keys.map do |e_or_k|
          key = e_or_k.respond_to?(:key) ? e_or_k.key.to_grpc : e_or_k.to_grpc
          Google::Datastore::V1beta3::Mutation.new(delete: key)
        end
      end
    end
  end
end
