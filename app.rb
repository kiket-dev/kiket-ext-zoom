# frozen_string_literal: true

require "sinatra/base"
require "json"
require "net/http"
require "uri"
require "base64"
require "logger"

# Zoom Notification Extension
# Handles sending notifications via Zoom chat using Server-to-Server OAuth
class ZoomNotificationExtension < Sinatra::Base
  configure do
    set :logging, true
    set :logger, Logger.new($stdout)
  end

  # Health check endpoint
  get "/health" do
    content_type :json
    {
      status: "healthy",
      service: "zoom-notifications",
      version: "1.0.0",
      timestamp: Time.now.utc.iso8601
    }.to_json
  end

  # Send notification endpoint
  post "/notify" do
    content_type :json

    begin
      request_body = JSON.parse(request.body.read, symbolize_names: true)

      # Validate required fields
      validate_notification_request!(request_body)

      # Get OAuth token
      access_token = get_zoom_access_token

      # Send message based on channel type
      result = case request_body[:channel_type]
      when "dm"
        send_direct_message(access_token, request_body)
      when "channel"
        send_channel_message(access_token, request_body)
      when "group"
        send_group_message(access_token, request_body)
      else
        raise ArgumentError, "Unsupported channel_type: #{request_body[:channel_type]}"
      end

      status 200
      {
        success: true,
        message_id: result[:message_id],
        delivered_at: Time.now.utc.iso8601
      }.to_json

    rescue JSON::ParserError => e
      logger.error "Invalid JSON: #{e.message}"
      status 400
      { success: false, error: "Invalid JSON in request body" }.to_json

    rescue ArgumentError => e
      logger.error "Validation error: #{e.message}"
      status 400
      { success: false, error: e.message }.to_json

    rescue ZoomAPIError => e
      logger.error "Zoom API error: #{e.message}"
      status 502
      {
        success: false,
        error: "Zoom API error: #{e.message}",
        retry_after: e.retry_after
      }.to_json

    rescue StandardError => e
      logger.error "Unexpected error: #{e.message}\n#{e.backtrace.join("\n")}"
      status 500
      { success: false, error: "Internal server error" }.to_json
    end
  end

  # Validate channel configuration
  post "/validate" do
    content_type :json

    begin
      request_body = JSON.parse(request.body.read, symbolize_names: true)

      # Get OAuth token to verify credentials
      access_token = get_zoom_access_token

      # Validate based on type
      case request_body[:channel_type]
      when "dm"
        validate_user_exists(access_token, request_body[:recipient_id])
      when "channel"
        validate_channel_exists(access_token, request_body[:channel_id])
      when "group"
        validate_group_exists(access_token, request_body[:channel_id])
      else
        raise ArgumentError, "Unsupported channel_type: #{request_body[:channel_type]}"
      end

      status 200
      {
        valid: true,
        message: "Channel configuration is valid"
      }.to_json

    rescue JSON::ParserError => e
      status 400
      { valid: false, error: "Invalid JSON in request body" }.to_json

    rescue ArgumentError => e
      status 400
      { valid: false, error: e.message }.to_json

    rescue ZoomAPIError => e
      status 200
      { valid: false, error: e.message }.to_json

    rescue StandardError => e
      logger.error "Unexpected error: #{e.message}"
      status 500
      { valid: false, error: "Internal server error" }.to_json
    end
  end

  private

  # Custom error for Zoom API issues
  class ZoomAPIError < StandardError
    attr_reader :retry_after

    def initialize(message, retry_after: nil)
      super(message)
      @retry_after = retry_after
    end
  end

  # Validate notification request has required fields
  def validate_notification_request!(request)
    raise ArgumentError, "message is required" if request[:message].nil? || request[:message].empty?
    raise ArgumentError, "channel_type is required" if request[:channel_type].nil?

    case request[:channel_type]
    when "dm"
      raise ArgumentError, "recipient_id is required for DM" if request[:recipient_id].nil?
    when "channel", "group"
      raise ArgumentError, "channel_id is required for channel/group" if request[:channel_id].nil?
    end
  end

  # Get Zoom OAuth access token using Server-to-Server OAuth
  def get_zoom_access_token
    account_id = ENV["ZOOM_ACCOUNT_ID"]
    client_id = ENV["ZOOM_CLIENT_ID"]
    client_secret = ENV["ZOOM_CLIENT_SECRET"]

    raise ArgumentError, "Missing Zoom OAuth credentials" if account_id.nil? || client_id.nil? || client_secret.nil?

    uri = URI("https://zoom.us/oauth/token")
    uri.query = URI.encode_www_form({
      grant_type: "account_credentials",
      account_id: account_id
    })

    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Basic #{Base64.strict_encode64("#{client_id}:#{client_secret}")}"

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(request)
    end

    unless response.is_a?(Net::HTTPSuccess)
      raise ZoomAPIError, "Failed to obtain access token: #{response.body}"
    end

    data = JSON.parse(response.body)
    data["access_token"]
  end

  # Send direct message to a Zoom user
  def send_direct_message(access_token, request)
    uri = URI("https://api.zoom.us/v2/chat/users/me/messages")

    http_request = Net::HTTP::Post.new(uri)
    http_request["Authorization"] = "Bearer #{access_token}"
    http_request["Content-Type"] = "application/json"

    payload = {
      to_contact: request[:recipient_id],
      message: format_message(request[:message], request[:format])
    }

    http_request.body = payload.to_json

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(http_request)
    end

    handle_zoom_response(response)
  end

  # Send message to a Zoom channel
  def send_channel_message(access_token, request)
    uri = URI("https://api.zoom.us/v2/chat/users/me/messages")

    http_request = Net::HTTP::Post.new(uri)
    http_request["Authorization"] = "Bearer #{access_token}"
    http_request["Content-Type"] = "application/json"

    payload = {
      to_channel: request[:channel_id],
      message: format_message(request[:message], request[:format])
    }

    # Add reply_main_message_id if threading is requested
    payload[:reply_main_message_id] = request[:thread_id] if request[:thread_id]

    http_request.body = payload.to_json

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(http_request)
    end

    handle_zoom_response(response)
  end

  # Send message to a Zoom group chat
  def send_group_message(access_token, request)
    # Group messages use the same endpoint as channel messages
    send_channel_message(access_token, request)
  end

  # Validate that a Zoom user exists
  def validate_user_exists(access_token, user_id)
    uri = URI("https://api.zoom.us/v2/users/#{user_id}")

    http_request = Net::HTTP::Get.new(uri)
    http_request["Authorization"] = "Bearer #{access_token}"

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(http_request)
    end

    unless response.is_a?(Net::HTTPSuccess)
      raise ZoomAPIError, "User not found or inaccessible: #{user_id}"
    end

    true
  end

  # Validate that a Zoom channel exists
  def validate_channel_exists(access_token, channel_id)
    uri = URI("https://api.zoom.us/v2/chat/channels/#{channel_id}")

    http_request = Net::HTTP::Get.new(uri)
    http_request["Authorization"] = "Bearer #{access_token}"

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(http_request)
    end

    unless response.is_a?(Net::HTTPSuccess)
      raise ZoomAPIError, "Channel not found or inaccessible: #{channel_id}"
    end

    true
  end

  # Validate that a Zoom group exists (alias for channel validation)
  def validate_group_exists(access_token, group_id)
    validate_channel_exists(access_token, group_id)
  end

  # Format message based on requested format
  def format_message(message, format)
    # Zoom supports markdown-like formatting
    case format
    when "markdown", nil
      message # Zoom's default format supports markdown
    when "plain"
      # Strip markdown formatting for plain text
      message.gsub(/[*_`~]/, "")
    when "html"
      # Zoom doesn't support HTML, convert basic tags
      message
        .gsub(/<br\s*\/?>/, "\n")
        .gsub(/<\/?p>/, "\n")
        .gsub(/<strong>(.*?)<\/strong>/, '*\1*')
        .gsub(/<b>(.*?)<\/b>/, '*\1*')
        .gsub(/<em>(.*?)<\/em>/, '_\1_')
        .gsub(/<i>(.*?)<\/i>/, '_\1_')
        .gsub(/<code>(.*?)<\/code>/, '`\1`')
        .gsub(/<[^>]+>/, "") # Remove remaining tags
    else
      message
    end
  end

  # Handle Zoom API response
  def handle_zoom_response(response)
    case response
    when Net::HTTPSuccess
      data = JSON.parse(response.body)
      { message_id: data["id"] }
    when Net::HTTPTooManyRequests
      retry_after = response["Retry-After"]&.to_i || 60
      raise ZoomAPIError.new("Rate limit exceeded", retry_after: retry_after)
    when Net::HTTPUnauthorized
      raise ZoomAPIError, "Unauthorized: Invalid or expired access token"
    when Net::HTTPForbidden
      raise ZoomAPIError, "Forbidden: Insufficient permissions"
    when Net::HTTPNotFound
      raise ZoomAPIError, "Not found: Channel or user does not exist"
    else
      raise ZoomAPIError, "Zoom API error: #{response.code} #{response.message}"
    end
  end
end
