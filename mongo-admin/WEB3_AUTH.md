# Web3 Authentication Setup

The MongoDB Admin UI supports Web3 wallet authentication for secure access control.

## Configuration

### Environment Variables

Add these to your `.env` file:

```bash
# Enable/disable Web3 authentication
WEB3_AUTH_ENABLED=true

# Comma-separated list of admin wallet addresses
ADMIN_WALLETS=0x1234567890123456789012345678901234567890,0x0987654321098765432109876543210987654321

# Session secret (change in production!)
SESSION_SECRET=your-secure-random-secret-here
```

### Enable Authentication

1. Set `WEB3_AUTH_ENABLED=true` in `.env`
2. Add your wallet addresses to `ADMIN_WALLETS` (comma-separated)
3. Set a secure `SESSION_SECRET`
4. Restart the container: `docker-compose restart mongo-admin`

### Disable Authentication

Set `WEB3_AUTH_ENABLED=false` in `.env` and restart.

## How It Works

1. **User connects wallet** - MetaMask or other Web3 wallet
2. **Signs message** - User signs a message to prove wallet ownership
3. **Server verifies** - Server verifies signature and checks if wallet is in admin list
4. **Session created** - If valid, a session is created for 24 hours
5. **Protected access** - All API endpoints require authentication when enabled

## Security Features

- ✅ Signature verification using ethers.js
- ✅ Session-based authentication (24-hour expiry)
- ✅ Wallet address whitelist
- ✅ All API endpoints protected
- ✅ Automatic logout on wallet removal from admin list

## Usage

1. Open the admin UI in your browser
2. If auth is enabled, you'll see a login modal
3. Click "Connect Wallet"
4. Approve the connection in your wallet
5. Sign the authentication message
6. You're now logged in!

## Notes

- Only wallets in the `ADMIN_WALLETS` list can access the UI
- Sessions expire after 24 hours
- You can logout using the logout button in the header
- If your wallet is removed from the admin list, you'll be logged out automatically
