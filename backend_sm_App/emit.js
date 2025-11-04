// emit.js
const { io } = require('socket.io-client');

const socket = io('http://localhost:5000', { transports: ['websocket'] });

socket.on('connect', () => {
  console.log('connected', socket.id);
  const payload = {
    user: 'node-test-client',
    latitude: 12.9716,
    longitude: 77.5946,
    timestamp: new Date().toISOString(),
    session: 'DEMO',
  };
  socket.emit('locationUpdate', payload);
  console.log('emitted', payload);
});

socket.on('locationUpdate', (d) => {
  console.log('locationUpdate recv', d);
});

socket.on('disconnect', () => console.log('disconnected'));
