// k6: nagły skok ruchu bez rozgrzewki. 20 s po jednym użytkowniku, potem od razu 40 naraz przez 40 s.
// Uruchom: k6 run demo/06-panic/skok.js   (-e URL=… gdy usługa ma inny adres)
import http from 'k6/http';
import { check } from 'k6';

const URL = __ENV.URL || 'http://panika.demo.127.0.0.1.sslip.io';

export const options = {
  scenarios: {
    skok: {
      executor: 'ramping-vus',
      startVUs: 1,
      stages: [
        { target: 1, duration: '20s' },   // spokój: 1 użytkownik
        { target: 40, duration: '1s' },   // skok: 40 naraz, bez rozgrzewki
        { target: 40, duration: '40s' },
        { target: 0, duration: '5s' },
      ],
    },
  },
};

export default function () {
  const body = JSON.stringify({ top: 'tryb panic', bottom: `uzytkownik ${__VU}`, scale: 2 });
  const res = http.post(`${URL}/api/memes`, body, { headers: { 'Content-Type': 'application/json' } });
  check(res, { 'mem utworzony (201)': (r) => r.status === 201 });
}
