const openButton = document.querySelector('[data-menu-open]');
const closeTargets = document.querySelectorAll('[data-menu-close]');
const menuPanel = document.querySelector('#mobile-menu');

function setMenuOpen(open) {
  document.body.classList.toggle('menu-open', open);
  openButton?.setAttribute('aria-expanded', String(open));
  menuPanel?.setAttribute('aria-hidden', String(!open));
}

openButton?.addEventListener('click', () => {
  setMenuOpen(!document.body.classList.contains('menu-open'));
});

closeTargets.forEach((target) => {
  target.addEventListener('click', () => setMenuOpen(false));
});

menuPanel?.querySelectorAll('a').forEach((link) => {
  link.addEventListener('click', () => setMenuOpen(false));
});

document.addEventListener('keydown', (event) => {
  if (event.key === 'Escape') setMenuOpen(false);
});
