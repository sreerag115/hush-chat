import express from 'express';
import http from 'http';
import { WebSocketServer, WebSocket } from 'ws';
import { v4 as uuidv4 } from 'uuid';
import path from 'path';
import fs from 'fs';

const app = express();
const server = http.createServer(app);
const wss = new WebSocketServer({ server });

const PORT = process.env.PORT || 8080;
const UPLOADS_DIR = path.join(__dirname, '../uploads');

// Ensure uploads directory exists
if (!fs.existsSync(UPLOADS_DIR)) {
  fs.mkdirSync(UPLOADS_DIR, { recursive: true });
}

app.use(express.json({ limit: '50mb' }));
app.use(express.urlencoded({ limit: '50mb', extended: true }));

interface User {
  username: string;
  publicKey: string; // Base64 Curve25519 public key
  isOnline: boolean;
  lastSeen: number;
}

// In-memory data store (for dev prototype)
const users = new Map<string, User>();
const activeConnections = new Map<string, WebSocket>();
const offlineMessages = new Map<string, any[]>(); // username -> messages[]

// API: Discover users and get their public keys
app.get('/users', (req, res) => {
  const userList = Array.from(users.values()).map(u => ({
    username: u.username,
    publicKey: u.publicKey,
    isOnline: activeConnections.has(u.username),
    lastSeen: u.lastSeen,
  }));
  res.json(userList);
});

// API: Get specific user public key
app.get('/users/:username', (req, res) => {
  const user = users.get(req.params.username);
  if (!user) {
    return res.status(404).json({ error: 'User not found' });
  }
  res.json({
    username: user.username,
    publicKey: user.publicKey,
    isOnline: activeConnections.has(user.username),
  });
});

// API: Upload encrypted file (e.g. voice notes)
app.post('/upload', (req, res) => {
  try {
    const { fileData, fileName } = req.body; // fileData is base64 string
    if (!fileData) {
      return res.status(400).json({ error: 'No file data provided' });
    }

    const fileId = uuidv4();
    const extension = fileName ? path.extname(fileName) : '.bin';
    const filePath = path.join(UPLOADS_DIR, `${fileId}${extension}`);

    const buffer = Buffer.from(fileData, 'base64');
    fs.writeFileSync(filePath, buffer);

    res.json({
      fileId,
      url: `/download/${fileId}${extension}`,
    });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
});

// API: Download encrypted file
app.get('/download/:fileId', (req, res) => {
  const fileId = req.params.fileId;
  const filePath = path.join(UPLOADS_DIR, fileId);

  if (!fs.existsSync(filePath)) {
    return res.status(404).json({ error: 'File not found' });
  }

  res.sendFile(filePath);
});

// WebSocket Server Handler
wss.on('connection', (ws: WebSocket) => {
  let authenticatedUsername: string | null = null;

  console.log('New WebSocket connection established.');

  ws.on('message', (messageStr: string) => {
    try {
      const data = JSON.parse(messageStr);

      switch (data.type) {
        case 'register': {
          const { username, publicKey } = data;
          if (!username || !publicKey) {
            ws.send(JSON.stringify({ type: 'error', message: 'Username and public key are required.' }));
            return;
          }

          // Register or update user
          users.set(username, {
            username,
            publicKey,
            isOnline: true,
            lastSeen: Date.now(),
          });

          authenticatedUsername = username;
          activeConnections.set(username, ws);
          console.log(`User registered: ${username}`);

          ws.send(JSON.stringify({ type: 'registered', username }));

          // Deliver pending offline messages
          const pending = offlineMessages.get(username);
          if (pending && pending.length > 0) {
            console.log(`Delivering ${pending.length} offline messages to ${username}`);
            pending.forEach(msg => ws.send(JSON.stringify(msg)));
            offlineMessages.delete(username);
          }

          // Broadcast user online status
          broadcast({
            type: 'status-change',
            username,
            isOnline: true,
          }, username);
          break;
        }

        case 'message': {
          if (!authenticatedUsername) {
            ws.send(JSON.stringify({ type: 'error', message: 'Unauthorized. Register first.' }));
            return;
          }

          const { to, payload, msgId, mediaType, timestamp } = data;
          const msgToForward = {
            type: 'message',
            from: authenticatedUsername,
            to,
            payload,
            msgId: msgId || uuidv4(),
            mediaType: mediaType || 'text',
            timestamp: timestamp || Date.now(),
          };

          const recipientWs = activeConnections.get(to);
          if (recipientWs && recipientWs.readyState === WebSocket.OPEN) {
            recipientWs.send(JSON.stringify(msgToForward));
            ws.send(JSON.stringify({ type: 'ack', msgId: msgToForward.msgId, status: 'delivered' }));
          } else {
            // Queue message offline
            if (!offlineMessages.has(to)) {
              offlineMessages.set(to, []);
            }
            offlineMessages.get(to)!.push(msgToForward);
            ws.send(JSON.stringify({ type: 'ack', msgId: msgToForward.msgId, status: 'queued' }));
          }
          break;
        }

        // WebRTC Signaling Forwarding
        case 'call-invite':
        case 'call-accept':
        case 'ice-candidate':
        case 'call-hangup': {
          if (!authenticatedUsername) return;
          const { to } = data;
          const recipientWs = activeConnections.get(to);
          if (recipientWs && recipientWs.readyState === WebSocket.OPEN) {
            // Forward signal, injecting the correct "from"
            recipientWs.send(JSON.stringify({
              ...data,
              from: authenticatedUsername,
            }));
          } else {
            ws.send(JSON.stringify({
              type: 'call-error',
              to,
              message: `User ${to} is offline.`,
            }));
          }
          break;
        }

        case 'heartbeat':
          ws.send(JSON.stringify({ type: 'heartbeat-ack' }));
          break;

        default:
          ws.send(JSON.stringify({ type: 'error', message: 'Unknown action type.' }));
      }
    } catch (e: any) {
      ws.send(JSON.stringify({ type: 'error', message: 'Invalid payload: ' + e.message }));
    }
  });

  ws.on('close', () => {
    if (authenticatedUsername) {
      activeConnections.delete(authenticatedUsername);
      console.log(`User disconnected: ${authenticatedUsername}`);

      const user = users.get(authenticatedUsername);
      if (user) {
        user.isOnline = false;
        user.lastSeen = Date.now();
      }

      broadcast({
        type: 'status-change',
        username: authenticatedUsername,
        isOnline: false,
      }, authenticatedUsername);
    }
  });
});

// Helper to broadcast status changes to other users
function broadcast(message: any, excludeUsername?: string) {
  const msgStr = JSON.stringify(message);
  activeConnections.forEach((ws, username) => {
    if (username !== excludeUsername && ws.readyState === WebSocket.OPEN) {
      ws.send(msgStr);
    }
  });
}

server.listen(PORT, () => {
  console.log(`WhisperChat backend listening on port ${PORT}`);
});
