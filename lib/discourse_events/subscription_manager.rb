# frozen_string_literal: true
module DiscourseEvents
  class SubscriptionManager
    PRODUCTS = {
      community: "prod_RHux1cdd4puCl4",
      business: "prod_RHuzahTrqKrkkY",
      enterprise: "prod_RHv03ip2qGhfsh",
    }.freeze

    BUCKETS = {
      community: "discourse-events-gems-community",
      business: "discourse-events-gems-business",
      enterprise: "discourse-events-gems-business",
    }.freeze

    GEMS = {
      community: {
        omnievent: "0.1.0.pre11",
        omnievent_icalendar: "0.1.0.pre9",
      },
      business: {
        omnievent: "0.1.0.pre11",
        omnievent_icalendar: "0.1.0.pre9",
        omnievent_api: "0.1.0.pre5",
        omnievent_outlook: "0.1.0.pre11",
        omnievent_google: "0.1.0.pre8",
      },
      enterprise: {
        omnievent: "0.1.0.pre11",
        omnievent_icalendar: "0.1.0.pre9",
        omnievent_api: "0.1.0.pre5",
        omnievent_outlook: "0.1.0.pre11",
        omnievent_google: "0.1.0.pre8",
      },
    }.freeze

    attr_writer :subscriptions

    def features
      result = {
        provider: {
          provider_type: {
            icalendar: {
              none: false,
              community: true,
              business: true,
              enterprise: true,
            },
            google: {
              none: false,
              community: false,
              business: true,
              enterprise: true,
            },
            outlook: {
              none: false,
              community: false,
              business: true,
              enterprise: true,
            },
          },
        },
        source: {
          import_type: {
            import: {
              none: false,
              community: true,
              business: true,
              enterprise: true,
            },
            import_publish: {
              none: false,
              community: false,
              business: true,
              enterprise: true,
            },
            publish: {
              none: false,
              community: false,
              business: true,
              enterprise: true,
            },
          },
          topic_sync: {
            manual: {
              none: false,
              community: true,
              business: true,
              enterprise: true,
            },
            auto: {
              none: false,
              community: true,
              business: true,
              enterprise: true,
            },
          },
          client: {
            discourse_events: {
              none: false,
              community: true,
              business: true,
              enterprise: true,
            },
          },
        },
      }

      if DiscourseEvents::Source.available_clients.include?("discourse_calendar")
        result[:source][:client][:discourse_calendar] = {
          none: false,
          community: false,
          business: true,
          enterprise: true,
        }
      end

      result
    end

    def self.setup(update: false, install: false)
      new.setup(update: update, install: install)
    end

    def ready?
      omnievent_installed?
    end

    def ready_to_setup?
      database_ready? && subscription_client_installed?
    end

    def setup(update: false, install: false)
      return unless ready_to_setup?
      perform_update if update
      perform_install if subscribed? && install
    end

    def perform_update
      ::DiscourseSubscriptionClient::Subscriptions.update
    end

    def perform_install
      return unless s3_gem.ready?
      s3_gem.install(GEMS[product.to_sym])
    end

    def s3_gem
      @s3_gem ||=
        DiscourseSubscriptionClient::S3Gem.new(
          plugin_name: "discourse-events",
          access_key_id: s3_gem_access_key_id,
          secret_access_key: s3_gem_secret_access_key,
          region: s3_gem_region,
          bucket: s3_gem_bucket,
        )
    end

    def s3_gem_access_key_id
      ENV["DISCOURSE_EVENTS_GEMS_S3_ACCESS_KEY_ID"] || subscriptions.resource&.access_key_id
    end

    def s3_gem_secret_access_key
      ENV["DISCOURSE_EVENTS_GEMS_S3_SECRET_ACCESS_KEY"] || subscriptions.resource&.secret_access_key
    end

    def s3_gem_region
      ENV["DISCOURSE_EVENTS_GEMS_S3_REGION"] || subscriptions.resource&.region
    end

    def s3_gem_bucket
      ENV["DISCOURSE_EVENTS_GEMS_S3_BUCKET"] || BUCKETS[product]
    end

    def subscribed?
      return true if ENV["DISCOURSE_EVENTS_PRODUCT"].present?
      subscription.present?
    end

    def supports_import?
      supports?(:source, :import_type, :import) || supports?(:source, :import_type, :import_publish)
    end

    def supports_publish?
      supports?(:source, :import_type, :publish) ||
        supports?(:source, :import_type, :import_publish)
    end

    def supports?(feature, attribute, value)
      return true unless feature && attribute && value
      return false unless product
      features.dig(feature.to_sym, attribute.to_sym, value.to_sym, product.to_sym)
    end

    def resource
      @resource ||= ::SubscriptionClientResource.find_by(name: "discourse-events")
    end

    def supplier
      resource ? resource.supplier : nil
    end

    def subscriptions
      @subscriptions ||= ::DiscourseSubscriptionClient.find_subscriptions("discourse-events")
    end

    def subscription
      @subscription ||=
        begin
          return enterprise_subscription if enterprise_subscription.present?
          return business_subscription if business_subscription.present?
          return community_subscription if community_subscription.present?
          nil
        end
    end

    def product
      @product ||=
        begin
          return ENV["DISCOURSE_EVENTS_PRODUCT"] if ENV["DISCOURSE_EVENTS_PRODUCT"].present?
          return nil unless subscription
          PRODUCTS.key(subscription.product_id)
        end
    end

    def community_subscription
      @community_subscription ||=
        begin
          return nil unless subscriptions && subscriptions.subscriptions
          subscriptions.subscriptions.find do |subscription|
            subscription.product_id == PRODUCTS[:community]
          end
        end
    end

    def business_subscription
      @business_subscription ||=
        begin
          return nil unless subscriptions && subscriptions.subscriptions
          subscriptions.subscriptions.find do |subscription|
            subscription.product_id == PRODUCTS[:business]
          end
        end
    end

    def enterprise_subscription
      @enterprise_subscription ||=
        begin
          return nil unless subscriptions && subscriptions.subscriptions
          subscriptions.subscriptions.find do |subscription|
            subscription.product_id == PRODUCTS[:enterprise]
          end
        end
    end

    def database_ready?
      Discourse.running_in_rack? && ActiveRecord::Base.connection&.table_exists?(
        "subscription_client_subscriptions"
      )
    rescue ActiveRecord::NoDatabaseError
      false
    end

    def subscription_client_installed?
      defined?(DiscourseSubscriptionClient) == "constant" &&
        DiscourseSubscriptionClient.class == Module
    end

    def omnievent_installed?
      defined?(OmniEvent) == "constant" && OmniEvent.class == Module
    end
  end
end
