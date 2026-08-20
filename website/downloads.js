const platformButtons = document.querySelectorAll('[data-platform-button]');
const platformPanels = document.querySelectorAll('[data-platform-panel]');
const recommendation = document.querySelector('#device-recommendation');

function detectPlatform() {
  const userAgent = navigator.userAgent.toLowerCase();
  const isIPad = navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1;

  if (userAgent.includes('android')) return 'android';
  if (/iphone|ipad|ipod/.test(userAgent) || isIPad) return 'ios';
  return 'desktop';
}

function selectPlatform(platform, detected = false) {
  platformButtons.forEach((button) => {
    const selected = button.dataset.platformButton === platform;
    button.setAttribute('aria-selected', String(selected));
    button.tabIndex = selected ? 0 : -1;
  });

  platformPanels.forEach((panel) => {
    panel.hidden = panel.dataset.platformPanel !== platform;
  });

  const labels = {
    desktop: 'Web-App für deinen Desktop',
    android: 'Android-Download für dein Gerät',
    ios: 'Safernotes für iPhone und iPad',
  };
  recommendation.textContent = detected
    ? `Empfohlen: ${labels[platform]}`
    : labels[platform];
}

platformButtons.forEach((button) => {
  button.addEventListener('click', () => {
    selectPlatform(button.dataset.platformButton);
  });
});

selectPlatform(detectPlatform(), true);
