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
