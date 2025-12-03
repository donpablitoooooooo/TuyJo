require('dotenv').config();
const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const cors = require('cors');

const authRoutes = require('./routes/auth');
const messageRoutes = require('./routes/messages');
const userRoutes = require('./routes/users');
const { authenticateSocket } = require('./middleware/auth');

const app = express();
const server = http.createServer(app);
const io = new Server(server, {
  cors: {
    origin: '*', // In produzione, specifica i domini consentiti
    methods: ['GET', 'POST'],
  },
});

// Middleware
app.use(cors());
app.use(express.json());

// Routes
app.use('/api/auth', authRoutes);
app.use('/api/messages', messageRoutes);
app.use('/api/users', userRoutes);

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// Socket.io connection handling
io.use(authenticateSocket);

io.on('connection', (socket) => {
  console.log(`User connected: ${socket.userId}`);

  // Join user to their own room
  socket.join(socket.userId);

  // Handle send message
  socket.on('send_message', async (data) => {
    try {
      const { receiverId, encryptedContent } = data;
      const senderId = socket.userId;

      // Save message to database
      const messageService = require('./services/messageService');
      const message = await messageService.saveMessage({
        senderId,
        receiverId,
        encryptedContent,
      });

      // Send to receiver if online
      io.to(receiverId).emit('new_message', message);

      // Send confirmation to sender
      socket.emit('new_message', message);

      // Send push notification if receiver is offline
      const userService = require('./services/userService');
      const receiverSockets = await io.in(receiverId).fetchSockets();
      if (receiverSockets.length === 0) {
        const receiver = await userService.getUserById(receiverId);
        if (receiver && receiver.fcmToken) {
          const notificationService = require('./services/notificationService');
          await notificationService.sendPushNotification(
            receiver.fcmToken,
            'Nuovo messaggio',
            'Hai ricevuto un nuovo messaggio'
          );
        }
      }
    } catch (error) {
      console.error('Error sending message:', error);
      socket.emit('error', { message: 'Failed to send message' });
    }
  });

  // Handle mark as read
  socket.on('mark_read', async (data) => {
    try {
      const { messageId } = data;
      const messageService = require('./services/messageService');
      await messageService.markAsRead(messageId);

      // Notify sender
      const message = await messageService.getMessageById(messageId);
      if (message) {
        io.to(message.senderId).emit('message_read', { messageId });
      }
    } catch (error) {
      console.error('Error marking message as read:', error);
    }
  });

  socket.on('disconnect', () => {
    console.log(`User disconnected: ${socket.userId}`);
  });
});

// Start server
const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
  console.log(`🚀 Server running on port ${PORT}`);
  console.log(`📱 Environment: ${process.env.NODE_ENV}`);
});
