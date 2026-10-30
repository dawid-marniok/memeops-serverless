// k6: symulacja keynote — cisza, nagły szczyt, powrót do ciszy.
// Uruchom: k6 run tools/keynote.js
//   -e URL=http://meme-gen.memeops.127.0.0.1.sslip.io   (domyślnie)
//   -e PEAK=100       żądań na sekundę w szczycie
//   -e SCALE=3        wielkość mema 1-8 (większy = więcej CPU na żądanie)
//   -e TOKEN=<JWT>    gdy funkcja wymaga logowania (LAB 6+)
import http from 'k6/http';
import { check } from 'k6';

const URL = __ENV.URL || 'http://meme-gen.memeops.127.0.0.1.sslip.io';
const PEAK = parseInt(__ENV.PEAK || '100');
const SCALE = parseInt(__ENV.SCALE || '3');
const TEXTS = ['Kiedy keynote się kończy', 'Deploy w piątek', 'Scale to zero', 'Cold start', 'Działa u mnie'];

export const options = {
  scenarios: {
    keynote: {
      executor: 'ramping-arrival-rate',
      startRate: 1, timeUnit: '1s', preAllocatedVUs: 50, maxVUs: 300,
      stages: [
        { target: 1, duration: '20s' },      // przed keynote: pojedyncze osoby
        { target: PEAK, duration: '10s' },   // keynote się kończy: wszyscy naraz
        { target: PEAK, duration: '60s' },   // szczyt
        { target: 0, duration: '20s' },      // rozchodzą się na kawę
      ],
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.01'],
    http_req_duration: ['p(95)<1000'],
  },
};

export default function () {
  const headers = { 'Content-Type': 'application/json' };
  if (__ENV.TOKEN) headers.Authorization = `Bearer ${__ENV.TOKEN}`;
  const body = JSON.stringify({
    top: TEXTS[Math.floor(Math.random() * TEXTS.length)], bottom: `uczestnik ${__VU}`, template: 'keynote', scale: SCALE,
  });
  const res = http.post(`${URL}/api/memes`, body, { headers });
  check(res, { 'mem utworzony (201)': (r) => r.status === 201 });
}
