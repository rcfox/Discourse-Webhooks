# name: webhooks
# about: Make HTTP requests when certain events occur
# version: 0.1
# authors: Ryan Fox
# url: https://github.com/rcfox/Discourse-Webhooks

require 'json'

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

      begin
        site_url = SiteSetting.webhooks_site_url
        if (not(site_url.end_with? "/"))
          site_url = "#{site_url}/"
        end

        topic_id = -1;
        if (event_name == "topic_created")
          topic_id = params[0].id
        elsif (event_name == "post_created")
          topic_id = params[0].topic_id
        end

        # Configure topic request
        topic_uri = URI.parse("#{site_url}t/#{topic_id}.json")
        topic_http = Net::HTTP.new(topic_uri.host, topic_uri.port)
        topic_http.use_ssl = true if topic_uri.scheme == 'https'
        topic_http.verify_mode = OpenSSL::SSL::VERIFY_NONE
        topic_request = Net::HTTP::Get.new(topic_uri.path)

        # Send topic request
        Rails.logger.info("Getting topic from: #{topic_uri.to_s}")
        topic_response = topic_http.request(topic_request)
        topic_json = {}
        case topic_response
        when Net::HTTPSuccess then
          topic_json = JSON.parse(topic_response.body)
          Rails.logger.debug("event_name=#{event_name}\ntopic_json=#{topic_json}")
        else
          Rails.logger.error("[TOPIC ERROR] for #{topic_uri}: #{topic_response.code} - #{topic_response.message}")
        end


        if SiteSetting.webhooks_include_api_key
          api_key = ApiKey.find_by(user_id: nil)
          if not api_key
            Rails.logger.warn('Webhooks configured to include the "All User" API key, but it does not exist.')
          else
            params.unshift(api_key.key)
          end
        end

        # Build webhook request
        uri = URI.parse(build_event_url(SiteSetting.webhooks_url_format, event_name))
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true if uri.scheme == 'https'
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE unless SiteSetting.webhooks_verify_ssl

        request = Net::HTTP::Post.new(uri.path)
        request.add_field('Content-Type', 'application/json')

        # Make topic link
        topic_link = "[#{topic_json["title"]}](#{site_url}t/#{topic_json["slug"]}/#{topic_json["id"]})"

        # Make webhook body
        known_event = false
        if (event_name == "topic_created")
          body = {:message => "#{params[2].username} created topic #{topic_link}", :metadata => event_name}
          request.body = body.to_json
          known_event = true
        elsif (event_name == "post_created")
          body = {:message => "#{params[2].username} posted in #{topic_link}:\n\n#{params[1]["raw"]}", :metadata => event_name}
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
        elsif (topic_json["archetype"] != "regular")
          # Ignore unknown archetypes
          if (SiteSetting.webhooks_logging_enabled)
            Rails.logger.debug("topic_json[\"archetype\"] -> #{topic_json["archetype"]}")

            if (topic_json["archetype"].to_s != "regular")
              Rails.logger.debug("topic_json[archetype].to_s != regular (double quotes)")
            elsif (topic_json["archetype"].to_s != 'regular')
              Rails.logger.debug("topic_json[archetype].to_s != regular (single quotes)")
            else
              Rails.logger.debug("[EQUAL] topic_json[\"archetype\"].to_s")
            end

            Rails.logger.info("Ignoring unknown archetype for event #{event_name}: #{topic_json}")
          end
          next
        end

        # Log params object
        if (SiteSetting.webhooks_logging_enabled)
          Rails.logger.info("Webhook event #{event_name}: #{params.to_json}")
        end

        # Send webhook request
        response = http.request(request)
        case response
        when Net::HTTPSuccess then
          # nothing
        else
          Rails.logger.error("#{uri}: #{response.code} - #{response.message}")
        end
      rescue => ex
        Rails.logger.error(ex.message)
      end
    end

  end

end
