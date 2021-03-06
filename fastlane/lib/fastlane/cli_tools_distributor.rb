module Fastlane
  # This class is responsible for checking the ARGV
  # to see if the user wants to launch another fastlane
  # tool or fastlane itself
  class CLIToolsDistributor
    class << self
      def running_version_command?
        ARGV.include?('-v') || ARGV.include?('--version')
      end

      def running_help_command?
        ARGV.include?('-h') || ARGV.include?('--help')
      end

      def take_off
        before_import_time = Time.now

        require "fastlane" # this might take a long time if there is no Gemfile :(

        # We want to avoid printing output other than the version number if we are running `fastlane -v`
        unless running_version_command?
          print_bundle_exec_warning(is_slow: (Time.now - before_import_time > 3))
        end

        unless (ENV['LANG'] || "").end_with?("UTF-8") || (ENV['LC_ALL'] || "").end_with?("UTF-8")
          warn = "WARNING: fastlane requires your locale to be set to UTF-8. To learn more go to https://docs.fastlane.tools/getting-started/ios/setup/#set-up-environment-variables"
          UI.error(warn)
          at_exit do
            # Repeat warning here so users hopefully see it
            UI.error(warn)
          end
        end

        FastlaneCore::UpdateChecker.start_looking_for_update('fastlane')

        ARGV.unshift("spaceship") if ARGV.first == "spaceauth"
        tool_name = ARGV.first ? ARGV.first.downcase : nil

        tool_name = process_emojis(tool_name)

        if tool_name && Fastlane::TOOLS.include?(tool_name.to_sym) && !available_lanes.include?(tool_name.to_sym)
          # Triggering a specific tool
          # This happens when the users uses things like
          #
          #   fastlane sigh
          #   fastlane snapshot
          #
          require tool_name
          begin
            # First, remove the tool's name from the arguments
            # Since it will be parsed by the `commander` at a later point
            # and it must not contain the binary name
            ARGV.shift

            # Import the CommandsGenerator class, which is used to parse
            # the user input
            require File.join(tool_name, "commands_generator")

            # Call the tool's CommandsGenerator class and let it do its thing
            commands_generator = Object.const_get(tool_name.fastlane_module)::CommandsGenerator
          rescue LoadError
            # This will only happen if the tool we call here, doesn't provide
            # a CommandsGenerator class yet
            # When we launch this feature, this should never be the case
            abort("#{tool_name} can't be called via `fastlane #{tool_name}`, run '#{tool_name}' directly instead".red)
          end
          commands_generator.start
        elsif tool_name == "fastlane-credentials"
          require 'credentials_manager'
          ARGV.shift
          CredentialsManager::CLI.new.run
        else
          # Triggering fastlane to call a lane
          require "fastlane/commands_generator"
          Fastlane::CommandsGenerator.start
        end
      ensure
        FastlaneCore::UpdateChecker.show_update_status('fastlane', Fastlane::VERSION)
      end

      # Since fastlane also supports the rocket and biceps emoji as executable
      # we need to map those to the appropriate tools
      def process_emojis(tool_name)
        return {
          "🚀" => "fastlane",
          "💪" => "gym"
        }[tool_name] || tool_name
      end

      def print_bundle_exec_warning(is_slow: false)
        return if FastlaneCore::Helper.bundler? # user is alread using bundler
        return if FastlaneCore::Env.truthy?('SKIP_SLOW_FASTLANE_WARNING') # user disabled the warnings
        return if FastlaneCore::Helper.contained_fastlane? # user uses the bundled fastlane

        gemfile_path = PluginManager.new.gemfile_path
        if gemfile_path
          # The user has a Gemfile, but forgot to use `bundle exec`
          # Let's tell the user how to use `bundle exec`
          # We show this warning no matter if the command is slow or not
          UI.important "fastlane detected a Gemfile in the current directory"
          UI.important "however it seems like you don't use `bundle exec`"
          UI.important "to launch fastlane faster, please use"
          UI.message ""
          UI.command "bundle exec fastlane #{ARGV.join(' ')}"
          UI.message ""
        elsif is_slow
          # fastlane is slow and there is no Gemfile
          # Let's tell the user how to use `gem cleanup` and how to
          # start using a Gemfile
          UI.important "Seems like launching fastlane takes a while - please run"
          UI.message ""
          UI.command "[sudo] gem cleanup"
          UI.message ""
          UI.important "to uninstall outdated gems and make fastlane launch faster"
          UI.important "Alternatively it's recommended to start using a Gemfile to lock your dependencies"
          UI.important "To get started with a Gemfile, run"
          UI.message ""
          UI.command "bundle init"
          UI.command "echo 'gem \"fastlane\"' >> Gemfile"
          UI.command "bundle install"
          UI.message ""
          UI.important "After creating the Gemfile and Gemfile.lock, commit those files into version control"
        end
        UI.important "Get started using a Gemfile for fastlane https://docs.fastlane.tools/getting-started/ios/setup/#use-a-gemfile"

        sleep 2 # napping is life, otherwise the user might not see this message
      end

      # Returns an array of symbols for the available lanes for the Fastfile
      # This doesn't actually use the Fastfile parser, but only
      # the available lanes. This way it's much faster, which
      # is very important in this case, since it will be executed
      # every time one of the tools is launched
      # Use this only if performance is :key:
      def available_lanes
        fastfile_path = FastlaneCore::FastlaneFolder.fastfile_path
        return [] if fastfile_path.nil?
        output = `cat #{fastfile_path.shellescape} | grep \"^\s*lane \:\" | awk -F ':' '{print $2}' | awk -F ' ' '{print $1}'`
        return output.strip.split(" ").collect(&:to_sym)
      end
    end
  end
end
