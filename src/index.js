// lab-01 — A tiny quote service.
// Owner: group:default/guests

const quotes = [
  'Ship the paved road, not the pothole.',
  'A catalog entry a day keeps the tribal knowledge away.',
];

function randomQuote() {
  return quotes[Math.floor(Math.random() * quotes.length)];
}

console.log(`["lab-01"] ${randomQuote()}`);
