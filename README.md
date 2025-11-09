# Zoom Notifications Extension

Send notifications via Zoom chat channels and direct messages using Server-to-Server OAuth.

## Features

- **Direct Messages**: Send notifications to individual Zoom users
- **Channel Messages**: Post to Zoom chat channels
- **Group Messages**: Notify group chats
- **Rich Formatting**: Support for markdown and HTML formatting
- **Validation**: Pre-flight checks for channel and user configuration
- **Error Handling**: Comprehensive error handling with retry guidance
- **Rate Limiting**: Automatic rate limit detection with retry-after headers

## Prerequisites

1. **Zoom Account**: You need a Zoom account with admin privileges
2. **Server-to-Server OAuth App**: Create a Server-to-Server OAuth app in the Zoom App Marketplace
3. **Required Scopes**:
   - `chat_message:write` - Send chat messages
   - `chat_channel:read` - Read channel information
   - `user:read` - Read user information

## Setup

### 1. Create Zoom Server-to-Server OAuth App

1. Go to [Zoom App Marketplace](https://marketplace.zoom.us/)
2. Click "Develop" → "Build App"
3. Choose "Server-to-Server OAuth"
4. Fill in app details:
   - App Name: "Kiket Notifications"
   - Company Name: Your organization
   - Developer Contact: Your email
5. Add required scopes:
   - `chat_message:write`
   - `chat_channel:read`
   - `user:read`
6. Activate the app
7. Copy credentials:
   - Account ID
   - Client ID
   - Client Secret

### 2. Configure Extension

Create a `.env` file with your Zoom credentials:

```bash
ZOOM_ACCOUNT_ID=your_account_id
ZOOM_CLIENT_ID=your_client_id
ZOOM_CLIENT_SECRET=your_client_secret
```

### 3. Install Dependencies

```bash
bundle install
```

## Development

### Run Locally

```bash
bundle exec rackup -p 9292
```

The extension will be available at `http://localhost:9292`

### Run Tests

```bash
bundle exec rspec
```

### Check Code Style

```bash
bundle exec rubocop
```

## CI/CD

The extension uses GitHub Actions for continuous integration and deployment:

### Continuous Integration (CI)

On every push to `main` or `develop` branches and on pull requests:
- ✅ Runs RuboCop linting
- ✅ Executes RSpec test suite
- ✅ Builds Docker image for amd64 and arm64 architectures
- ✅ Pushes images to GitHub Container Registry (ghcr.io)

### Release Process

On tagged releases (e.g., `v1.0.0`):
1. Runs full test suite
2. Builds multi-platform Docker images (linux/amd64, linux/arm64)
3. Pushes tagged images to GitHub Container Registry:
   - `ghcr.io/kiket-dev/kiket-ext-zoom:1.0.0`
   - `ghcr.io/kiket-dev/kiket-ext-zoom:1.0`
   - `ghcr.io/kiket-dev/kiket-ext-zoom:1`
   - `ghcr.io/kiket-dev/kiket-ext-zoom:latest`
4. Creates GitHub Release with auto-generated release notes

**To create a release:**
```bash
git tag v1.0.0
git push origin v1.0.0
```

## API Endpoints

### Health Check

```bash
GET /health
```

Returns service health status.

**Response:**
```json
{
  "status": "healthy",
  "service": "zoom-notifications",
  "version": "1.0.0",
  "timestamp": "2025-11-09T12:00:00Z"
}
```

### Send Notification

```bash
POST /notify
Content-Type: application/json
```

Send a notification to Zoom.

**Request Body:**
```json
{
  "message": "Your notification message",
  "channel_type": "dm",
  "recipient_id": "user@example.com",
  "format": "markdown",
  "priority": "normal",
  "metadata": {
    "source": "workflow-123"
  }
}
```

**Parameters:**
- `message` (required): The notification message content
- `channel_type` (required): Type of destination - `dm`, `channel`, or `group`
- `recipient_id` (required for DM): Zoom user email or ID
- `channel_id` (required for channel/group): Zoom channel ID
- `format` (optional): Message format - `markdown` (default), `plain`, or `html`
- `priority` (optional): Message priority - `low`, `normal` (default), `high`, `urgent`
- `thread_id` (optional): Message ID to reply to (for threading)
- `metadata` (optional): Additional metadata (not sent to Zoom)

**Response (Success):**
```json
{
  "success": true,
  "message_id": "msg-123",
  "delivered_at": "2025-11-09T12:00:00Z"
}
```

**Response (Error):**
```json
{
  "success": false,
  "error": "Error description",
  "retry_after": 60
}
```

### Validate Channel

```bash
POST /validate
Content-Type: application/json
```

Validate that a channel or user exists and is accessible.

**Request Body:**
```json
{
  "channel_type": "dm",
  "recipient_id": "user@example.com"
}
```

**Response (Valid):**
```json
{
  "valid": true,
  "message": "Channel configuration is valid"
}
```

**Response (Invalid):**
```json
{
  "valid": false,
  "error": "User not found or inaccessible: user@example.com"
}
```

## Usage Examples

### Send Direct Message

```bash
curl -X POST http://localhost:9292/notify \
  -H "Content-Type: application/json" \
  -d '{
    "message": "Hello from Kiket!",
    "channel_type": "dm",
    "recipient_id": "user@example.com"
  }'
```

### Send Channel Message

```bash
curl -X POST http://localhost:9292/notify \
  -H "Content-Type: application/json" \
  -d '{
    "message": "New deployment completed successfully!",
    "channel_type": "channel",
    "channel_id": "ABC123XYZ"
  }'
```

### Send with Rich Formatting

```bash
curl -X POST http://localhost:9292/notify \
  -H "Content-Type: application/json" \
  -d '{
    "message": "**Alert**: System maintenance in *30 minutes*",
    "channel_type": "channel",
    "channel_id": "ABC123XYZ",
    "format": "markdown",
    "priority": "high"
  }'
```

### Validate User Exists

```bash
curl -X POST http://localhost:9292/validate \
  -H "Content-Type: application/json" \
  -d '{
    "channel_type": "dm",
    "recipient_id": "user@example.com"
  }'
```

## Deployment

### Docker (GitHub Container Registry)

The extension is automatically built and published to GitHub Container Registry on every release.

**Pull the latest image:**
```bash
docker pull ghcr.io/kiket-dev/kiket-ext-zoom:latest
```

**Pull a specific version:**
```bash
docker pull ghcr.io/kiket-dev/kiket-ext-zoom:1.0.0
```

**Run the container:**
```bash
docker run -p 9292:9292 \
  -e ZOOM_ACCOUNT_ID=your_account_id \
  -e ZOOM_CLIENT_ID=your_client_id \
  -e ZOOM_CLIENT_SECRET=your_client_secret \
  ghcr.io/kiket-dev/kiket-ext-zoom:latest
```

### Docker (Build from Source)

Build and run the Docker container locally:

```bash
docker build -t kiket-zoom-extension .

docker run -p 9292:9292 \
  -e ZOOM_ACCOUNT_ID=your_account_id \
  -e ZOOM_CLIENT_ID=your_client_id \
  -e ZOOM_CLIENT_SECRET=your_client_secret \
  kiket-zoom-extension
```

### Environment Variables

Required:
- `ZOOM_ACCOUNT_ID`: Zoom Server-to-Server OAuth Account ID
- `ZOOM_CLIENT_ID`: Zoom Server-to-Server OAuth Client ID
- `ZOOM_CLIENT_SECRET`: Zoom Server-to-Server OAuth Client Secret

Optional:
- `PORT`: Port to bind to (default: 9292)
- `RACK_ENV`: Environment (default: production)
- `WEB_CONCURRENCY`: Number of Puma workers (default: 2)
- `RAILS_MAX_THREADS`: Threads per worker (default: 5)

## Error Handling

The extension handles various error scenarios:

- **400 Bad Request**: Invalid request (missing required fields, invalid JSON)
- **502 Bad Gateway**: Zoom API errors (rate limits, authentication failures)
- **500 Internal Server Error**: Unexpected errors

Rate limiting errors include a `retry_after` field indicating seconds to wait before retry.

## Finding Zoom IDs

### User Email/ID
Use the user's Zoom email address or find their ID via:
```bash
curl -X GET "https://api.zoom.us/v2/users/{email}" \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN"
```

### Channel ID
1. In Zoom app, right-click the channel
2. Select "Copy Link"
3. Extract the channel ID from the URL

Or use the API:
```bash
curl -X GET "https://api.zoom.us/v2/chat/channels" \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN"
```

## Development Tips

1. **Use Zoom's Test Mode**: Test without sending real messages using mock endpoints
2. **Monitor Rate Limits**: Zoom has rate limits - respect `retry_after` headers
3. **Validate Early**: Use `/validate` endpoint before bulk operations
4. **Format Wisely**: Markdown is the most compatible format across Zoom clients

## Troubleshooting

### "Unauthorized" errors
- Verify your OAuth credentials are correct
- Check that your app has the required scopes
- Ensure the app is activated in Zoom App Marketplace

### "Not found" errors
- Verify the channel/user ID is correct
- Ensure your app has access to the channel
- Check that the user is in your Zoom account

### Rate limiting
- Implement exponential backoff
- Use the `retry_after` value from error responses
- Consider batching messages

## License

MIT License - see LICENSE file for details

## Support

For issues and questions:
- Extension issues: [GitHub Issues](https://github.com/kiket-dev/kiket-ext-zoom/issues)
- Kiket platform: [Kiket Support](mailto:support@kiket.dev)
- Zoom API: [Zoom Developer Forum](https://devforum.zoom.us/)
