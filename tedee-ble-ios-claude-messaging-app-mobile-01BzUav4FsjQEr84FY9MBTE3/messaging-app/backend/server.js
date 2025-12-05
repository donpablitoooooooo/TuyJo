require('dotenv').config();
const express = require('express');
const http = require('http');
const WebSocket = require('ws');
const cors = require('cors');
const jwt = require('jsonwebtoken');
const url = require('url');

const authRoutes = require('./routes/auth');
const messageRoutes = require('./routes/messages');
const userRoutes = require('./routes/users');

const app = express();
const server = http.createServer(app);

// WebSocket server
const wss = new WebSocket.Server({ server });

// Middleware
app.use(cors());
app.use(express.json());

// Store WebSocket connections (userId -> WebSocket)
const connections = new Map();

// Make connections available to routes
app.set('io', {
  to: (userId) => ({
    emit: (event, data) => {
      const ws = connections.get(userId);
      if (ws && ws.readyState === WebSocket.OPEN) {
        ws.send(JSON.stringify({ event, data }));
      }
    },
  }),
});

// Routes
app.use('/api/auth', authRoutes);
app.use('/api/messages', messageRoutes);
app.use('/api/users', userRoutes);

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// WebSocket connection handling
wss.on('connection', (ws, req) => {
  console.log('🔌 New WebSocket connection');

  // Parse query params for token
  const params = url.parse(req.url, true).query;
  const token = params.token;

  if (!token) {
    console.log('❌ No token provided');
    ws.close(1008, 'No token provided');
    return;
  }

  try {
    // Verify JWT token
    const decoded = jwt.verify(token, process.env.JWT_SECRET);
    const userId = decoded.userId;

    console.log(`✅ User authenticated: ${userId}`);

    // Store connection
    connections.set(userId, ws);

    // Send confirmation
    ws.send(
      JSON.stringify({
        event: 'connected',
        data: { user_id: userId },
      })
    );

    // Handle disconnect
    ws.on('close', () => {
      console.log(`❌ User disconnected: ${userId}`);
      connections.delete(userId);
    });

    // Handle errors
    ws.on('error', (error) => {
      console.error(`❌ WebSocket error for ${userId}:`, error);
      connections.delete(userId);
    });

    // Handle ping/pong for keepalive
    ws.on('pong', () => {
      ws.isAlive = true;
    });

    ws.isAlive = true;
  } catch (error) {
    console.error('❌ Token verification failed:', error.message);
    ws.close(1008, 'Invalid token');
  }
});

// Heartbeat to detect broken connections
const heartbeatInterval = setInterval(() => {
  wss.clients.forEach((ws) => {
    if (ws.isAlive === false) {
      return ws.terminate();
    }

    ws.isAlive = false;
    ws.ping();
  });
}, 30000); // Every 30 seconds

wss.on('close', () => {
  clearInterval(heartbeatInterval);
});

// Start server
const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
  console.log(`🚀 Server running on port ${PORT}`);
  console.log(`📱 Environment: ${process.env.NODE_ENV}`);
  console.log(`🔌 WebSocket ready at ws://localhost:${PORT}`);
});
