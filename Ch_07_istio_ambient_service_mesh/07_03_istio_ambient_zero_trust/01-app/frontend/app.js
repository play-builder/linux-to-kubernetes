const http = require('http');

const API_URL = process.env.API_URL || 'http://api.shop.svc.cluster.local:8080';
const PORT = 8080;

const server = http.createServer(async (req, res) => {
  if (req.url === '/healthz') {
    res.writeHead(200); res.end('ok'); return;
  }
  try {
    const data = await new Promise((resolve, reject) => {
      http.get(`${API_URL}/products`, (r) => {
        let body = ''; r.on('data', c => body += c);
        r.on('end', () => resolve(body));
      }).on('error', reject);
    });
    res.writeHead(200, {'Content-Type': 'application/json'});
    res.end(JSON.stringify({ service: 'frontend', upstream: JSON.parse(data) }));
  } catch (e) {
    res.writeHead(502); res.end(JSON.stringify({ error: e.message }));
  }
});

server.listen(PORT, () => console.log(`frontend listening on ${PORT}`));
