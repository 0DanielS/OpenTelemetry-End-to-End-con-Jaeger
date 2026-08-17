import http from 'k6/http';
import { check } from 'k6';

const VUS = parseInt(__ENV.VUS || '50', 10);
const DURATION = __ENV.DURATION || '5m';

export const options = {
  vus: VUS,
  duration: DURATION,
  thresholds: {
    http_req_duration: ['p(99)<500'],
    http_req_failed: ['rate<0.01'],
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';

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
