require 'base64'

module Travis
  # Decrypts a single configuration value from a configuration file using the
  # repository's SSL key.
  #
  # This is used so people can add encrypted sensitive data to their
  # `.travis.yml` file.
  class SecureConfig < Struct.new(:key)
    require 'travis/secure_config/obfuscate'

    MSGS = {
      decrypt_failed: 'Error decrypting config value for %s: %s'
    }

    class << self
      def decrypt(config, key)
        new(key).decrypt(config)
      end

      def encrypt(config, key)
        new(key).encrypt(config)
      end

      def obfuscate(config, key)
        Obfuscate.new(config, key).run
      end
    end

    def decrypt(config)
      return config if config.nil? || config.is_a?(String)

      config.inject(config.class.new) do |result, element|
        key, element = element if result.is_a?(Hash)
        value = process(result, key, decrypt_element(key, element))
        block_given? ? yield(value) : value
      end
    end

    def encrypt(config)
      { 'secure' => key.encode(config) }
    end

    def obfuscate(config)
    end

    private

      def decrypt_element(key, element)
        if element.is_a?(Array) || element.is_a?(Hash)
          decrypt(element)
        elsif secure_key?(key) && element
          decrypt_value(element)
        else
          element
        end
      rescue => e
        Travis::Addons.logger.warn(MSGS[:decrypt_failed] % [key.repository.slug, string])
        nil
      end

      def process(result, key, value)
        if result.is_a?(Array)
          result << value
        elsif result.is_a?(Hash) && !secure_key?(key)
          result[key] = value
          result
        else
          value
        end
      end

      def decrypt_value(value)
        decoded = Base64.decode64(value)
        # TODO should probably be checked earlier
        if key.respond_to?(:decrypt)
          key.decrypt(decoded)
        else
          puts "Can not decrypt secure config value: #{value.inspect[0..10]} using key: #{key.inspect[0..10]}"
        end
      rescue OpenSSL::PKey::RSAError => e
        value
      end

      def secure_key?(key)
        key && (key == :secure || key == 'secure')
      end
  end
end
