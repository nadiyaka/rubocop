# frozen_string_literal: true

module RuboCop
  module Cop
    module Rails
      # This cop checks for the correct use of Date methods,
      # such as Date.today, Date.current etc.
      #
      # Using `Date.today` is dangerous, because it doesn't know anything about
      # Rails time zone. You must use `Time.zone.today` instead.
      #
      # The cop also reports warnings when you are using `to_time` method,
      # because it doesn't know about Rails time zone either.
      #
      # Two styles are supported for this cop. When EnforcedStyle is 'strict'
      # then the Date methods `today`, `current`, `yesterday`, and `tomorrow`
      # are prohibited and the usage of both `to_time`
      # and 'in_time_zone' are reported as warning.
      #
      # When EnforcedStyle is 'flexible' then only `Date.today` is prohibited
      # and only `to_time` is reported as warning.
      #
      # @example EnforcedStyle: strict
      #   # bad
      #   Date.current
      #   Date.yesterday
      #   Date.today
      #   date.to_time
      #   date.in_time_zone
      #
      #   # good
      #   Time.zone.today
      #   Time.zone.today - 1.day
      #
      # @example EnforcedStyle: flexible (default)
      #   # bad
      #   Date.today
      #   date.to_time
      #
      #   # good
      #   Time.zone.today
      #   Time.zone.today - 1.day
      #   Date.current
      #   Date.yesterday
      #   date.in_time_zone
      #
      # `to_time_in_current_zone` is a deprecated method.
      # This cop identifies places where `to_time_in_current_zone`
      # can be replaced by `in_time_zone`.
      #
      # @example
      #   # bad
      #    "2016-07-12 14:36:31".to_time_in_current_zone
      #
      #   # good
      #    "2016-07-12 14:36:31".in_time_zone
      #
      class Date < Cop
        include ConfigurableEnforcedStyle

        MSG = 'Do not use `Date.%<day>s` without zone. Use ' \
              '`Time.zone.%<day>s` instead.'.freeze

        MSG_SEND = 'Do not use `%<method>s` on Date objects, because they ' \
                   'know nothing about the time zone in use.'.freeze

        BAD_DAYS = %i[today current yesterday tomorrow].freeze

        DEPRECATED_MSG = '`%<deprecated_method>s` is deprecated. ' \
                         'Use `%<relevant_method>s` instead.'.freeze

        def on_const(node)
          mod, klass = *node.children
          # we should only check core Date class (`Date` or `::Date`)
          return unless (mod.nil? || mod.cbase_type?) && method_send?(node)

          check_date_node(node.parent) if klass == :Date
        end

        def on_send(node)
          if node.method_name == :to_time_in_current_zone
            add_offense(node, location: :selector,
                              message: format(DEPRECATED_MSG, deprecated_method: 'to_time_in_current_zone', relevant_method: 'in_time_zone'))
          end

          return unless node.receiver && bad_methods.include?(node.method_name)

          return if safe_chain?(node) || safe_to_time?(node)

          add_offense(node, location: :selector,
                            message: format(MSG_SEND, method: node.method_name))
        end

        private

        def check_date_node(node)
          chain = extract_method_chain(node)

          return if (chain & bad_days).empty?

          method_name = (chain & bad_days).join('.')

          add_offense(node, location: :selector,
                            message: format(MSG, day: method_name.to_s))
        end

        def extract_method_chain(node)
          [node, *node.each_ancestor(:send)].map(&:method_name)
        end

        # checks that parent node of send_type
        # and receiver is the given node
        def method_send?(node)
          return false unless node.parent && node.parent.send_type?

          node.parent.receiver == node
        end

        def safe_chain?(node)
          chain = extract_method_chain(node)

          (chain & bad_methods).empty? || !(chain & good_methods).empty?
        end

        def safe_to_time?(node)
          return unless node.method?(:to_time)

          if node.receiver.str_type?
            zone_regexp = /([+-][\d:]+|\dZ)\z/

            node.receiver.str_content.match(zone_regexp)
          else
            node.arguments.one?
          end
        end

        def good_days
          style == :strict ? [] : %i[current yesterday tomorrow]
        end

        def bad_days
          BAD_DAYS - good_days
        end

        def bad_methods
          style == :strict ? %i[to_time in_time_zone] : [:to_time]
        end

        def good_methods
          style == :strict ? [] : TimeZone::ACCEPTED_METHODS
        end
      end
    end
  end
end
