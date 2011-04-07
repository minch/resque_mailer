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
          new_args = objects_to_model_hashes(*args)
          ::Resque.enqueue(self, "#{method_name}!", new_args)
        else super(method_name, *args)
        end
      end

      def perform(cmd, *args)
        send(cmd, *args)
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

        tmp.each_with_index do |arg, index|
          next unless arg.is_a? Hash

          new_arg = {}
          arg.each do |k, v|
            if v.respond_to?(:id) and ( v.id != v.object_id)
              args[index] = { k => { :id => v.id, :model => v.class.name } }
            end
          end
        end

        args.present? && args.size == 1 ? args.first : args
      end

      #
      # This method is called by the given mailer after it receives a deliver that
      # was sent through the above (objects_to_ids)
      #
      def objects_from_model_hashes(*args)
      end

      def logger
        RAILS_DEFAULT_LOGGER rescue nil
      end
    end
  end
end
