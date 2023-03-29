require "json"
require "logger"

require "sinatra/base"
require 'sinatra/custom_logger'

module SlackBot
  class Application < Sinatra::Base
    helpers Sinatra::CustomLogger

    set :logger, Rails.logger

    private def bot_id
      @bot_id ||= fetch_bot_id
    end

    private def fetch_bot_id
      bot_id = if ENV["APP_ENV"] == "test"
                 "TEST_BOT_ID"
               else
                 slack_client = Slack::Web::Client.new
                 bot_info = slack_client.auth_test
                 bot_info["user_id"]
               end
    ensure
      logger.info "bot_id = #{bot_id}"
    end

    ALLOW_CHANNEL_IDS = ENV.fetch("ALLOW_CHANNEL_IDS", "").split(/\s+|,\s*/)

    private def allowed_channel?(channel)
      if ALLOW_CHANNEL_IDS.empty?
        true
      else
        ALLOW_CHANNEL_IDS.include?(channel.slack_id)
      end
    end

    private def thread_context_prohibited?(channel)
      true
    end

    before "/events" do
      Slack::Events::Request.new(request).verify!
    end

    error Slack::Events::Request::MissingSigningSecret do
      status 500
    end

    error Slack::Events::Request::InvalidSignature do
      status 400
    end

    post "/events" do
      request_data = JSON.parse(request.body.read)

      case request_data["type"]
      when "url_verification"
        request_data["challenge"]

      when "event_callback"
        event = request_data["event"]

        # Non-thread message:
        # {"client_msg_id"=>"58e6675f-c164-451a-8354-7c7085ddba33",
        #  "type"=>"app_mention",
        #  "text"=>"<@U04U7QNHCD9> 以下を日本語に翻訳してください:\n" + "\n" + "Brands and...",
        #  "user"=>"U036WLG7H",
        #  "ts"=>"1679639978.922569",
        #  "blocks"=>
        #   [{"type"=>"rich_text",
        #     "block_id"=>"G8jBl",
        #     "elements"=>
        #      [{"type"=>"rich_text_section",
        #        "elements"=>
        #         [{"type"=>"user", "user_id"=>"U04U7QNHCD9"},
        #          {"type"=>"text",
        #           "text"=>" 以下を日本語に翻訳してください:\n" + "\n" + "Brands and..."}]}]}],
        #  "team"=>"T036WLG7F",
        #  "channel"=>"C036WLG7Z",
        #  "event_ts"=>"1679639978.922569"}

        # Reply in thread:
        # {"client_msg_id"=>"56846932-4600-4161-9947-a164084bf559",
        #  "type"=>"app_mention",
        #  "text"=>"<@U04U7QNHCD9> スレッド返信のテストです。",
        #  "user"=>"U036WLG7H",
        #  "ts"=>"1679644228.326869",
        #  "blocks"=>
        #   [{"type"=>"rich_text",
        #     "block_id"=>"EHX",
        #     "elements"=>
        #      [{"type"=>"rich_text_section",
        #        "elements"=>
        #         [{"type"=>"user", "user_id"=>"U04U7QNHCD9"},
        #          {"type"=>"text", "text"=>" スレッド返信のテストです。"}]}]}],
        #  "team"=>"T036WLG7F",
        #  "thread_ts"=>"1679640009.398859",
        #  "parent_user_id"=>"U04U7QNHCD9",
        #  "channel"=>"C036WLG7Z",
        #  "event_ts"=>"1679644228.326869"}

        if event["type"] == "app_mention"
          team = event["team"]
          channel = ensure_conversation(event["channel"])
          user = ensure_user(event["user"], channel)
          ts = event["ts"]
          thread_ts = event["thread_ts"]
          text = event["text"]

          if allowed_channel?(channel)
            logger.info "Event:\n" + event.pretty_inspect.each_line.map {|l| "> #{l}" }.join("")
            logger.info "#{channel.slack_id}: #{text}"

            if thread_ts && thread_context_prohibited?(channel)
              response = "Sorry, we can't continue the conversation within threads on this channel! Please mention me outside threads."
              Utils.post_ephemeral(
                channel: channel.slack_id,
                user: user.slack_id,
                thread_ts: ts,
                text: response,
                blocks: [
                  {
                    type: "section",
                    text: {
                      type: "mrkdwn",
                      text: "*#{response}*"
                    }
                  }
                ]
              )
            else
              case text
              when /^<@#{bot_id}>\s+/
                Message.create!(conversation: channel, user: user, text: text, slack_ts: ts, slack_thread_ts: thread_ts || ts)

                message_body = Regexp.last_match.post_match
                job_params = {
                  "channel" => channel.slack_id,
                  "user" => user.slack_id,
                  "ts" => ts,
                  "message" => message_body,
                }
                params["thread_ts"] = thread_ts if thread_ts
                ChatCompletionJob.perform_later(job_params)
              end
            end
          end
        end

        status 200
      end
    end

    private def ensure_user(user_id, channel)
      user = User.find_by_slack_id(user_id)
      user = fetch_user!(user_id) if user.blank?
      unless channel.members.include?(user)
        channel.members << user
      end
      user
    end

    private def ensure_conversation(channel_id)
      channel = Conversation.find_by_slack_id(channel_id)
      if channel.present?
        channel
      else
        fetch_conversation!(channel_id)
      end
    end

    private def fetch_user!(user_id)
      slack_client = Slack::Web::Client.new
      response = slack_client.users_info(user: user_id, include_locale: true)
      if response.ok
        User.create!(
          name: response.user.name,
          real_name: response.user.real_name,
          slack_id: response.user.id,
          locale: response.user.locale,
          email: response.user.profile.email,
          tz_offset: response.user.tz_offset.to_i
        )
      else
        raise "users.info with user=#{user_id} is failed"
      end
    end

    private def fetch_conversation!(channel_id)
      slack_client = Slack::Web::Client.new
      response = slack_client.conversations_info(channel: channel_id)
      if response.ok
        Conversation.create!(
          name: response.channel.name,
          slack_id: response.channel.id
        )
      else
        raise "conversations.info with channel=#{channel_id} is failed"
      end
    end
  end
end
