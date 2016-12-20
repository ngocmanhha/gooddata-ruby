# encoding: UTF-8
#
# Copyright (c) 2010-2016 GoodData Corporation. All rights reserved.
# This source code is licensed under the BSD-style license found in the
# LICENSE file in the root directory of this source tree.

require 'hashie'
require 'terminal-table'

require_relative 'actions/actions'
require_relative 'dsl/dsl'
require_relative 'helpers/helpers'

module GoodData
  module LCM2
    class SmartHash < Hash
      def method_missing(name, *args, &block)
        self[name.to_s.downcase.to_sym]
      end
    end

    MODES = {
      # Low Level Commands

      actions: [
        PrintActions
      ],

      hello: [
        HelloWorld
      ],

      modes: [
        PrintModes
      ],

      info: [
        PrintTypes,
        PrintActions,
        PrintModes
      ],

      types: [
        PrintTypes
      ],


      ## Bricks

      release: [
        CollectSegments,        # TODO: Implement
        CreateSegmentMasters,   # Done - tested
        EnsureUsers,            # TODO: Implement
        SynchronizeLdm,         # Done - tested
        SynchronizeLabelTypes,  # Done - tested
        SynchronizeMeta,        # Done - tested
        SynchronizeProcesses,   # Done - tested
        SynchronizeSchedules,   # Done - tested
        SynchronizeNewSegments, # Done - tested
        UpdateReleaseTable      # Done - tested
      ],

      provision: [
        CollectSegments,        # TODO: Implement
        PurgeClients,           # Done - tested
        CollectClients,         # Done - tested
        AssociateClients,       # Done - tested
        ProvisionClients,       # Done - tested
        EnsureUsers,            # TODO: Implement
        EnsureTitles,           # Done - tested
        SynchronizeLabelTypes,  # Done - tested
        SynchronizeProcesses,   # Done - tested
        SynchronizeSchedules,   # Done - tested
      ],

      rollout: [
        CollectSegments,        # TODO: Implement
        CollectClients,         # Done - tested
        EnsureUsers,            # TODO: Implement
        SynchronizeLdm,         # Done - tested
        SynchronizeLabelTypes,  # Done - tested
        SynchronizeProcesses,   # Done - tested
        SynchronizeSchedules,   # Done - tested
        SynchronizeClients,     # TODO: This is the moment when we update API segments from lcm_release table
      ],

      users: [
        EnsureUsersDomain,
        EnsureUsersProject,
      ]
    }

    MODE_NAMES = MODES.keys

    class << self
      def convert_params(params)
        # Symbolize all keys
        Hashie.symbolize_keys!(params)
        self.convert_to_smart_hash(params)
      end

      def convert_to_smart_hash(params)
        if params.kind_of?(Hash)
          res = SmartHash.new
          params.each_pair do |k, v|
            if v.kind_of?(Hash) || v.kind_of?(Array)
              res[k.downcase] = self.convert_to_smart_hash(v)
            else
              res[k.downcase] = v
            end
          end
          res
        elsif params.kind_of?(Array)
          params.map do |item|
            self.convert_to_smart_hash(item)
          end
        else
          params
        end
      end

      def get_mode_actions(mode)
        MODES[mode.to_sym] || fail("Invalid mode specified '#{mode}', supported modes are: '#{MODE_NAMES.join(', ')}'")
      end

      def print_action_names(mode, actions)
        title = "Actions to be performed for mode '#{mode}'"

        headings = %w(# NAME DESCRIPTION)

        rows = []
        actions.each_with_index do |action, index|
          rows << [index, action.short_name, action.const_defined?(:DESCRIPTION) && action.const_get(:DESCRIPTION)]
        end

        table = Terminal::Table.new :title => title, :headings => headings do |t|
          rows.each_with_index do |row, index|
            t << row
            t.add_separator if index < rows.length - 1
          end
        end
        puts table
      end

      def print_action_result(action, messages)
        title = "Result of #{action.short_name}"
        keys = (messages.first && messages.first.keys) || []
        headings = keys.map(&:upcase)

        rows = messages.map do |message|
          row = []
          keys.each do |heading|
            row << message[heading]
          end
          row
        end

        table = Terminal::Table.new :title => title, :headings => headings do |t|
          rows.each_with_index do |row, index|
            t << row
            t.add_separator if index < rows.length - 1
          end
        end

        puts table
      end

      def print_actions_result(actions, results)
        actions.each_with_index do |action, index|
          self.print_action_result(action, results[index])
          puts
        end
        nil
      end

      def perform(mode, params = {})
        params = self.convert_params(params)

        # Get actions for mode specified
        actions = self.get_mode_actions(mode)

        # Print name of actions to be performed for debug purposes
        self.print_action_names(mode, actions)

        # TODO: Check all action params first

        # Run actions
        results = actions.map do |action|
          # puts "Performing #{action.name}"

          puts

          # Invoke action
          out = action.send(:call, params)

          # Handle output results and params
          res = out.kind_of?(Array) ? out : out[:results]
          out_params = out.kind_of?(Hash) ? out[:params] || {} : {}
          new_params = self.convert_to_smart_hash(out_params)

          # Merge with new params
          params.merge!(new_params)

          # Print action result
          puts
          self.print_action_result(action, res)

          # Return result for final summary
          res
        end

        if actions.length > 1
          puts
          puts 'SUMMARY'
          puts

          # Print execution summary/results
          self.print_actions_result(actions, results)
        end
      end
    end
  end
end
