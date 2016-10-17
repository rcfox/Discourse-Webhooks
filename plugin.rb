# name: webhooks
# about: Make HTTP requests when certain events occur
# version: 0.1
# authors: Ryan Fox
# url: https://github.com/rcfox/Discourse-Webhooks

gem 'discourse_api'

after_initialize do

  SYSTEM_GUARDIAN = Guardian.new(User.find_by(id: -1))

  # Include the SSO record with all User data for staff requests so that you
  # can figure out which of your users triggered the current webhook request.
  UserSerializer.class_eval do
    staff_attributes :single_sign_on_record
  end

  User.class_eval do
    # User.as_json seems to be broken due to no User::View being defined?
    # I don't really know what that's about. Let's just hack around it!
    def as_json(options = nil)
      user_serializer = UserSerializer.new(self, scope: SYSTEM_GUARDIAN)
      user_serializer.serializable_hash
    end
  end

  def build_event_url(url_template, event_name)
    url = String.new(url_template)
    url.gsub!("%{event_name}", event_name)
    return url
  end

  SiteSetting.webhooks_registered_events.split('|').each do |event_name|

    DiscourseEvent.on(event_name.to_sym) do |*params|

      next unless SiteSetting.webhooks_enabled

      # Configure API client
      client = DiscourseApi::Client.new("http://localhost:3000")
      client.api_key = SiteSetting.webhooks_discourse_api_key
      client.api_username = SiteSetting.webhooks_discourse_api_username
      api_topic = client.topic(params[0].id)
      Rails.logger.info(api_topic)

      if SiteSetting.webhooks_include_api_key
        api_key = ApiKey.find_by(user_id: nil)
        if not api_key
          Rails.logger.warn('Webhooks configured to include the "All User" API key, but it does not exist.')
        else
          params.unshift(api_key.key)
        end
      end

      uri = URI.parse(build_event_url(SiteSetting.webhooks_url_format, event_name))
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true if uri.scheme == 'https'
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE unless SiteSetting.webhooks_verify_ssl

      request = Net::HTTP::Post.new(uri.path)
      request.add_field('Content-Type', 'application/json')

      # Make webhook body
      known_event = false
      if (event_name == "topic_created")
        link = "https://developer.mypurecloud.com/forum/t/#{params[0].slug}/#{params[0].id}"
        body = {:message => "#{params[2].username} created topic [#{params[1]["title"]}](#{link}):\n\n #{params[1]["raw"]}", :metadata => event_name}
        request.body = body.to_json
        known_event = true
      elsif (event_name == "post_created")
        body = {:message => "#{params[2].username} posted in a [thread](https://developer.mypurecloud.com/forum/t/#{params[0].topic_id}):\n\n #{params[1]["raw"]}", :metadata => event_name}
        request.body = body.to_json
        known_event = true
      end

      # Cancel processing
      if (known_event != true)
        # Ignore unknown events
        if (SiteSetting.webhooks_logging_enabled)
          Rails.logger.info("Ignoring #{event_name} event: #{params.to_json}")
        end
        next
      elsif (params[1].nil? || params[1]["archetype"] != "regular")
        # Ignore unknown archetypes
        if (SiteSetting.webhooks_logging_enabled)
          Rails.logger.info("Ignoring unknown archetype for event #{event_name}: #{params.to_json}")
        end
        next
      end

      # Log params object
      if (SiteSetting.webhooks_logging_enabled)
        Rails.logger.info("Webhook event #{event_name}: #{params.to_json}")
      end

      # Send request
      response = http.request(request)
      case response
      when Net::HTTPSuccess then
        # nothing
      else
        Rails.logger.error("#{uri}: #{response.code} - #{response.message}")
      end
    end

  end

end
