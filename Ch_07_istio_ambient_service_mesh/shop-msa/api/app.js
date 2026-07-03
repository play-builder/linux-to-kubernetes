const http = require('http');
const PORT = 8080;

const products = [
  { id: 1, name: 'Keyboard', price: 49 },
  { id: 2, name: 'Mouse', price: 29 },
  { id: 3, name: 'Monitor', price: 199 }
];

const server = http.createServer((req, res) => {
  if (req.url === '/healthz') {
    res.writeHead(200); res.end('ok'); return;
  }
  if (req.url === '/products') {
    res.writeHead(200, {'Content-Type': 'application/json'});
    res.end(JSON.stringify(products));
    return;
  }
  res.writeHead(404); res.end('not found');
});

server.listen(PORT, () => console.log(`api listening on ${PORT}`));

// --- graceful shutdown: SIGTERM 수신 시 새 연결 거부 + 진행 중 요청 완료 ---
process.on('SIGTERM', () => {
  console.log('SIGTERM received, draining...');
  server.close(() => { console.log('drained, bye'); process.exit(0); });
  // grace 기간(30s)보다 짧은 안전 상한 — 8초 내 못 끝나면 자발 종료
  setTimeout(() => process.exit(0), 8000).unref();
});
