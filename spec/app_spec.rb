# frozen_string_literal: true

require "spec_helper"
require "base64"

RSpec.describe ZoomNotificationExtension do
  let(:zoom_account_id) { "test-account-id" }
  let(:zoom_client_id) { "test-client-id" }
  let(:zoom_client_secret) { "test-client-secret" }
  let(:access_token) { "test-access-token-123" }

  before do
    ENV["ZOOM_ACCOUNT_ID"] = zoom_account_id
    ENV["ZOOM_CLIENT_ID"] = zoom_client_id
    ENV["ZOOM_CLIENT_SECRET"] = zoom_client_secret
  end

  after do
    ENV.delete("ZOOM_ACCOUNT_ID")
    ENV.delete("ZOOM_CLIENT_ID")
    ENV.delete("ZOOM_CLIENT_SECRET")
  end

  describe "GET /health" do
    it "returns healthy status" do
      get "/health"

      expect(last_response).to be_ok
      expect(last_response.content_type).to include("application/json")

      body = JSON.parse(last_response.body)
      expect(body["status"]).to eq("healthy")
      expect(body["service"]).to eq("zoom-notifications")
      expect(body["version"]).to eq("1.0.0")
      expect(body["timestamp"]).to match(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/)
    end
  end

  describe "POST /notify" do
    let(:oauth_stub) do
      stub_request(:post, "https://zoom.us/oauth/token")
        .with(
          query: {
            grant_type: "account_credentials",
            account_id: zoom_account_id
          },
          headers: {
            "Authorization" => "Basic #{Base64.strict_encode64("#{zoom_client_id}:#{zoom_client_secret}")}"
          }
        )
        .to_return(
          status: 200,
          body: { access_token: access_token }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    context "with direct message" do
      let(:request_body) do
        {
          message: "Hello from Kiket!",
          channel_type: "dm",
          recipient_id: "user@example.com",
          format: "markdown"
        }
      end

      let(:zoom_message_stub) do
        stub_request(:post, "https://api.zoom.us/v2/chat/users/me/messages")
          .with(
            headers: {
              "Authorization" => "Bearer #{access_token}",
              "Content-Type" => "application/json"
            },
            body: {
              to_contact: "user@example.com",
              message: "Hello from Kiket!"
            }.to_json
          )
          .to_return(
            status: 200,
            body: { id: "msg-123" }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "sends direct message successfully" do
        oauth_stub
        zoom_message_stub

        post "/notify", request_body.to_json, { "CONTENT_TYPE" => "application/json" }

        expect(last_response).to be_ok
        body = JSON.parse(last_response.body)
        expect(body["success"]).to be true
        expect(body["message_id"]).to eq("msg-123")
        expect(body["delivered_at"]).to match(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/)
      end
    end

    context "with channel message" do
      let(:request_body) do
        {
          message: "Channel announcement",
          channel_type: "channel",
          channel_id: "channel-456",
          format: "markdown"
        }
      end

      let(:zoom_message_stub) do
        stub_request(:post, "https://api.zoom.us/v2/chat/users/me/messages")
          .with(
            headers: {
              "Authorization" => "Bearer #{access_token}",
              "Content-Type" => "application/json"
            },
            body: {
              to_channel: "channel-456",
              message: "Channel announcement"
            }.to_json
          )
          .to_return(
            status: 200,
            body: { id: "msg-456" }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "sends channel message successfully" do
        oauth_stub
        zoom_message_stub

        post "/notify", request_body.to_json, { "CONTENT_TYPE" => "application/json" }

        expect(last_response).to be_ok
        body = JSON.parse(last_response.body)
        expect(body["success"]).to be true
        expect(body["message_id"]).to eq("msg-456")
      end
    end

    context "with validation errors" do
      it "returns error when message is missing" do
        post "/notify", { channel_type: "dm", recipient_id: "user@example.com" }.to_json,
             { "CONTENT_TYPE" => "application/json" }

        expect(last_response.status).to eq(400)
        body = JSON.parse(last_response.body)
        expect(body["success"]).to be false
        expect(body["error"]).to include("message is required")
      end

      it "returns error when channel_type is missing" do
        post "/notify", { message: "Test" }.to_json, { "CONTENT_TYPE" => "application/json" }

        expect(last_response.status).to eq(400)
        body = JSON.parse(last_response.body)
        expect(body["success"]).to be false
        expect(body["error"]).to include("channel_type is required")
      end

      it "returns error when recipient_id is missing for DM" do
        post "/notify", { message: "Test", channel_type: "dm" }.to_json,
             { "CONTENT_TYPE" => "application/json" }

        expect(last_response.status).to eq(400)
        body = JSON.parse(last_response.body)
        expect(body["success"]).to be false
        expect(body["error"]).to include("recipient_id is required for DM")
      end

      it "returns error when channel_id is missing for channel" do
        post "/notify", { message: "Test", channel_type: "channel" }.to_json,
             { "CONTENT_TYPE" => "application/json" }

        expect(last_response.status).to eq(400)
        body = JSON.parse(last_response.body)
        expect(body["success"]).to be false
        expect(body["error"]).to include("channel_id is required")
      end

      it "returns error for invalid JSON" do
        post "/notify", "invalid json", { "CONTENT_TYPE" => "application/json" }

        expect(last_response.status).to eq(400)
        body = JSON.parse(last_response.body)
        expect(body["success"]).to be false
        expect(body["error"]).to include("Invalid JSON")
      end
    end

    context "with Zoom API errors" do
      let(:request_body) do
        {
          message: "Test",
          channel_type: "dm",
          recipient_id: "user@example.com"
        }
      end

      it "handles rate limiting" do
        oauth_stub
        stub_request(:post, "https://api.zoom.us/v2/chat/users/me/messages")
          .to_return(status: 429, headers: { "Retry-After" => "60" })

        post "/notify", request_body.to_json, { "CONTENT_TYPE" => "application/json" }

        expect(last_response.status).to eq(502)
        body = JSON.parse(last_response.body)
        expect(body["success"]).to be false
        expect(body["error"]).to include("Rate limit exceeded")
        expect(body["retry_after"]).to eq(60)
      end

      it "handles unauthorized errors" do
        oauth_stub
        stub_request(:post, "https://api.zoom.us/v2/chat/users/me/messages")
          .to_return(status: 401)

        post "/notify", request_body.to_json, { "CONTENT_TYPE" => "application/json" }

        expect(last_response.status).to eq(502)
        body = JSON.parse(last_response.body)
        expect(body["success"]).to be false
        expect(body["error"]).to include("Unauthorized")
      end

      it "handles not found errors" do
        oauth_stub
        stub_request(:post, "https://api.zoom.us/v2/chat/users/me/messages")
          .to_return(status: 404)

        post "/notify", request_body.to_json, { "CONTENT_TYPE" => "application/json" }

        expect(last_response.status).to eq(502)
        body = JSON.parse(last_response.body)
        expect(body["success"]).to be false
        expect(body["error"]).to include("Not found")
      end
    end
  end

  describe "POST /validate" do
    let(:oauth_stub) do
      stub_request(:post, "https://zoom.us/oauth/token")
        .to_return(
          status: 200,
          body: { access_token: access_token }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    context "with valid user" do
      let(:request_body) do
        {
          channel_type: "dm",
          recipient_id: "user@example.com"
        }
      end

      let(:zoom_user_stub) do
        stub_request(:get, "https://api.zoom.us/v2/users/user@example.com")
          .with(headers: { "Authorization" => "Bearer #{access_token}" })
          .to_return(
            status: 200,
            body: { id: "user@example.com", email: "user@example.com" }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "validates user successfully" do
        oauth_stub
        zoom_user_stub

        post "/validate", request_body.to_json, { "CONTENT_TYPE" => "application/json" }

        expect(last_response).to be_ok
        body = JSON.parse(last_response.body)
        expect(body["valid"]).to be true
        expect(body["message"]).to include("valid")
      end
    end

    context "with invalid user" do
      let(:request_body) do
        {
          channel_type: "dm",
          recipient_id: "nonexistent@example.com"
        }
      end

      let(:zoom_user_stub) do
        stub_request(:get, "https://api.zoom.us/v2/users/nonexistent@example.com")
          .to_return(status: 404)
      end

      it "returns invalid for nonexistent user" do
        oauth_stub
        zoom_user_stub

        post "/validate", request_body.to_json, { "CONTENT_TYPE" => "application/json" }

        expect(last_response).to be_ok
        body = JSON.parse(last_response.body)
        expect(body["valid"]).to be false
        expect(body["error"]).to include("not found")
      end
    end

    context "with valid channel" do
      let(:request_body) do
        {
          channel_type: "channel",
          channel_id: "channel-123"
        }
      end

      let(:zoom_channel_stub) do
        stub_request(:get, "https://api.zoom.us/v2/chat/channels/channel-123")
          .with(headers: { "Authorization" => "Bearer #{access_token}" })
          .to_return(
            status: 200,
            body: { id: "channel-123", name: "General" }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "validates channel successfully" do
        oauth_stub
        zoom_channel_stub

        post "/validate", request_body.to_json, { "CONTENT_TYPE" => "application/json" }

        expect(last_response).to be_ok
        body = JSON.parse(last_response.body)
        expect(body["valid"]).to be true
      end
    end
  end

  describe "message formatting" do
    let(:oauth_stub) do
      stub_request(:post, "https://zoom.us/oauth/token")
        .to_return(
          status: 200,
          body: { access_token: access_token }.to_json
        )
    end

    context "with HTML format" do
      let(:request_body) do
        {
          message: "<strong>Bold</strong> and <em>italic</em> text",
          channel_type: "dm",
          recipient_id: "user@example.com",
          format: "html"
        }
      end

      let(:zoom_message_stub) do
        stub_request(:post, "https://api.zoom.us/v2/chat/users/me/messages")
          .with(
            body: hash_including(
              message: "*Bold* and _italic_ text"
            )
          )
          .to_return(
            status: 200,
            body: { id: "msg-123" }.to_json
          )
      end

      it "converts HTML to markdown" do
        oauth_stub
        zoom_message_stub

        post "/notify", request_body.to_json, { "CONTENT_TYPE" => "application/json" }

        expect(last_response).to be_ok
      end
    end
  end
end
