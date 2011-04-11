module Resque
  module Mailer
    module ClassMethods

      def current_env
        RAILS_ENV
      end

      def method_missing(method_name, *args)
        return super if environment_excluded?

        case method_name.id2name
        when /^deliver_([_a-z]\w*)\!/ then super(method_name, *args)
        when /^deliver_([_a-z]\w*)/ then
          ::Resque.enqueue(self, "#{method_name}!", objects_to_model_hashes(*args))
        else super(method_name, *args)
        end
      end

      def perform(cmd, *args)
        send(cmd, objects_from_model_hashes(*args))
      end

      private
      #
      # Resque doesn't marshal objects over redis.
      #
      # So we replace any key value pairs that contain model objects w/a hash
      # that contains the modeal name and the id.  On the other side, i.e. in
      # the given mailer, we can "deserialize" these back to a hash that contains
      # the actual models.
      #
      # E.g.
      #
      # :user => (some user object w/id 1971)
      #
      # becomes
      #
      # :user => { :model => 'User', :id => 1971 }
      #
      def objects_to_model_hashes(*args)
        tmp = *args.dup
        tmp = [ tmp ] unless tmp.is_a? Array
        results = []

        tmp.each_with_index do |arg, index|
          result = nil

          unless arg.is_a? Hash
            results.push(arg)
            next
          end

          new_arg = {}
          arg.each do |k, v|
            id = v.id rescue nil
            if id != v.object_id
              new_arg[k] = { :id => v.id, :model => v.class.name }
            else
              new_arg[k] = v
            end
          end

          results.push(new_arg)
        end

        results.present? && results.size == 1 ? results.first : results
      end

      #
      # This method is called by the given mailer after it receives a deliver that
      # was sent through the above (objects_to_model_hashes)
      #
      # E.g.
      #
      # :user => { :model => 'User', :id => 1971 }
      #
      # becomes
      #
      # :user => (some user object w/id 1971)
      #
      #
      def objects_from_model_hashes(*args)
        tmp = *args.dup
        tmp = [ tmp ] unless tmp.is_a? Array
        results = []

        tmp.each_with_index do |arg, index|
          result = nil

          unless arg.is_a? Hash
            results.push(arg)
            next
          end

          new_arg = {}
          arg.each do |k, v|
            unless v.is_a?(Hash)
              new_arg[k] = v
              next
            end

            # Keys come from redis as strings but need to normalize for any synchronous deliveries
            v = v.stringify_keys
            unless v.keys.include?("model") and v.keys.include?("id")
              next
            end

            klass = Object.const_get(v["model"])
            next unless klass
            o = klass.send :find, v["id"]
            next unless o

            new_arg[k] = o
          end

          results.push(new_arg)
        end

        results.present? && results.size == 1 ? results.first : results
      end

      def logger
        RAILS_DEFAULT_LOGGER rescue nil
      end
    end
  end
end
