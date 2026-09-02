import http from 'k6/http';
import { check, sleep } from 'k6';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';
const DATA_URL = __ENV.DATA_URL || 'http://localhost:8082';

export const options = {
  scenarios: {
    stats: {
      executor: 'constant-vus',
      vus: 3,
      duration: '4m20s',
      exec: 'stats',
      tags: { phase: 'stats' },
    },
    warmup: {
      executor: 'constant-vus',
      vus: 5,
      duration: '30s',
      startTime: '0s',
      tags: { phase: 'warmup' },
    },
    sustained: {
      executor: 'ramping-vus',
      startTime: '30s',
      startVUs: 10,
      stages: [
        { duration: '30s', target: 50 },
        { duration: '2m', target: 50 },
        { duration: '30s', target: 10 },
      ],
      tags: { phase: 'sustained' },
    },
    spike: {
      executor: 'ramping-vus',
      startTime: '3m30s',
      startVUs: 10,
      stages: [
        { duration: '10s', target: 150 },
        { duration: '30s', target: 150 },
        { duration: '10s', target: 10 },
      ],
      tags: { phase: 'spike' },
    },
  },
  thresholds: {
    http_req_duration: ['p(99)<500'],
    http_req_failed: ['rate<0.01'],
  },
};

export default function () {
  const product_id = `p${(__VU % 100) + 1}`;
  const payload = JSON.stringify({
    product_id: product_id,
    quantity: 1,
    customer_id: `customer-${__VU}`,
  });

  const res = http.post(`${BASE_URL}/orders`, payload, {
    headers: { 'Content-Type': 'application/json' },
  });

  check(res, { 'status is 201': (r) => r.status === 201 });
}

export function stats() {
  const endpoint = __ITER % 2 === 0 ? '/stats/orders' : '/stats/top-products';
  const res = http.get(`${DATA_URL}${endpoint}`);
  check(res, { 'stats is 200': (r) => r.status === 200 });
  sleep(1);
}
