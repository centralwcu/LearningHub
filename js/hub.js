// Fun Facts
const funFacts = [
  "The first credit union in the U.S. was founded in 1909 in New Hampshire.",
  "Credit unions are not-for-profit financial cooperatives owned by their members.",
  "The largest credit union in the world is Navy Federal Credit Union.",
  "The first paper money was created in China over 1,000 years ago.",
  "Credit unions often offer better interest rates than traditional banks.",
  "Credit unions return profits to members through lower fees and better rates.",
  "The first credit card was introduced by Diners Club in 1950.",
  "The U.S. has more than 5,000 credit unions.",
  "The first coin was minted in Lydia (now Turkey) around 600 BC.",
  "Credit unions are governed by a volunteer board of directors.",
  "The word 'credit' comes from the Latin 'credere', meaning 'to believe'.",
  "Credit unions often support local community projects.",
  "The first check was written in England in 1659.",
  "Credit unions have a 'people helping people' philosophy.",
  "Credit unions serve over 120 million members in the U.S.",
  "The first debit card was introduced in 1966.",
  "Credit unions can be chartered by the state or federal government.",
  "Credit unions are known for personalized customer service.",
  "The word \"dollar\" comes from the German word \"thaler,\" a silver coin used throughout Europe.",
  "The first known use of a written check was in 9th-century Persia.",
  "In the 1950s, checks were processed by hand, leading to the invention of MICR (Magnetic Ink Character Recognition) to speed things up.",
  "The magnetic stripe on credit cards was invented by IBM in the 1960s.",
  "The original ATM used paper vouchers instead of plastic cards.",
  "The first mobile payment was made in 1997 in Finland, to buy a Coca-Cola from a vending machine.",
  "There are now over 3 million ATMs worldwide."
];
function showRandomFunFact() {
  const fact = funFacts[Math.floor(Math.random() * funFacts.length)];
  document.getElementById('funFactText').textContent = fact;
  document.getElementById('funFactCard').style.display = 'flex';
}
showRandomFunFact();

// Collapse sections
document.querySelectorAll('.collapse-toggle').forEach(header => {
  header.addEventListener('click', () => {
    const tgt = document.getElementById(header.getAttribute('aria-controls'));
    const open = tgt.classList.toggle('show');
    header.setAttribute('aria-expanded', open);
  });
  header.addEventListener('keydown', e => {
    if (e.key === 'Enter' || e.key === ' ') header.click();
  });
});


// Search
const searchInput = document.getElementById('searchInput');
const clearBtn = document.getElementById('clearSearch');
clearBtn.addEventListener('click', () => {
  searchInput.value = '';
  clearBtn.style.display = 'none';
  searchInput.dispatchEvent(new Event('input'));
  searchInput.focus();
});
function highlightText(text, term) {
  if (!term) return text;
  return text.replace(new RegExp(`(${term.replace(/[.*+?^${}()|[\]\\]/g,'\\$&')})`, 'gi'),
    '<span class="search-highlight">$1</span>');
}
searchInput.addEventListener('input', () => {
  const search = searchInput.value.trim().toLowerCase();
  clearBtn.style.display = search ? 'block' : 'none';
  document.querySelectorAll('#guidesList .list-group-item').forEach(item => {
    const el = item.querySelector('a.btn, span.guide-pending');
    if (!el) return;
    const txt = el.textContent.trim().toLowerCase();
    const keys = (el.getAttribute('data-keywords')||'').toLowerCase();
    if (search) {
      if (txt.includes(search) || keys.includes(search)) {
        item.classList.remove('search-hidden');
        item.classList.add('search-match');
        el.innerHTML = highlightText(el.textContent, search);
      } else {
        item.classList.add('search-hidden');
        item.classList.remove('search-match');
        el.innerHTML = el.textContent;
      }
    } else {
      item.classList.remove('search-hidden');
      item.classList.remove('search-match');
      el.innerHTML = el.textContent;
    }
  });
  if (search) {
    document.getElementById('onlineBankingContent')?.classList.add('show');
    document.getElementById('mobileBankingContent')?.classList.add('show');
    document.getElementById('mobileBankingContentMobile')?.classList.add('show');
    document.getElementById('onlineBankingContentMobile')?.classList.add('show');
  }
});

// Favorites
const favoritesKey = 'cwcuFavorites';
function getFavorites() { return JSON.parse(localStorage.getItem(favoritesKey) || '[]'); }
function setFavorites(f) { localStorage.setItem(favoritesKey, JSON.stringify(f)); }
function isFavorite(url) { return getFavorites().some(f => f.url===url); }
function addFavorite(title, url) {
  const f = getFavorites();
  if (!f.some(x=>x.url===url)) {
    f.unshift({title, url});
    setFavorites(f);
    renderFavorites();
    addFavoriteStars();
  }
}
function removeFavorite(url) {
  setFavorites(getFavorites().filter(x=>x.url!==url));
  renderFavorites();
  addFavoriteStars();
}

let sortableFavorites = null;
function initSortableFavorites() {
  const favList = document.getElementById('favoritesList');
  if (sortableFavorites) sortableFavorites.destroy();
  sortableFavorites = new Sortable(favList, {
    animation: 180,
    ghostClass: 'sortable-ghost',
    handle: '.drag-handle',
    draggable: 'li',
    onEnd: () => {
      const newFavs = [];
      favList.querySelectorAll('li').forEach(li => {
        const b = li.querySelector('a.btn');
        if (b) newFavs.push({ title: b.textContent.trim(), url: b.getAttribute('href') });
      });
      setFavorites(newFavs);
    }
  });
}

function renderFavorites() {
  const sec = document.getElementById('favoritesSection');
  const list = document.getElementById('favoritesList');
  const f = getFavorites();
  list.innerHTML = '';
  if (!f.length) {
    sec.style.display = 'none';
    if (sortableFavorites) sortableFavorites.destroy();
    return;
  }
  sec.style.display = '';
  f.forEach(x => {
    const li = document.createElement('li');
    li.className = 'list-group-item d-flex align-items-center';
    const drag = document.createElement('span');
    drag.className = 'drag-handle';
    drag.innerHTML = '<i class="bi bi-grip-vertical"></i>';
    const btn = document.createElement('a');
    btn.className = 'btn btn-link text-decoration-none p-0';
    btn.setAttribute('href', x.url);
    btn.textContent = x.title;
    const star = document.createElement('button');
    star.className = 'favorite-btn favorited';
    star.innerHTML = '<i class="bi bi-star-fill"></i>';
    star.onclick = e => { e.stopPropagation(); removeFavorite(x.url); };
    li.appendChild(drag);
    li.appendChild(btn);
    li.appendChild(star);
    list.appendChild(li);
  });
  initSortableFavorites();
}

function addFavoriteStars() {
  document.querySelectorAll('#guidesList .list-group-item').forEach(item => {
    const btn = item.querySelector('a.btn');
    if (!btn) return;
    const url = btn.getAttribute('href');
    if (!url) return;
    if (!item.querySelector('.favorite-btn')) {
      const star = document.createElement('button');
      star.className = 'favorite-btn';
      star.innerHTML = '<i class="bi bi-star"></i>';
      star.onclick = e => {
        e.stopPropagation();
        if (isFavorite(url)) removeFavorite(url);
        else addFavorite(btn.textContent.trim(), url);
      };
      item.appendChild(star);
    }
    const starBtn = item.querySelector('.favorite-btn');
    if (isFavorite(url)) {
      starBtn.classList.add('favorited');
      starBtn.innerHTML = '<i class="bi bi-star-fill"></i>';
    } else {
      starBtn.classList.remove('favorited');
      starBtn.innerHTML = '<i class="bi bi-star"></i>';
    }
  });
}

// Initialize favorites & stars
renderFavorites();
setTimeout(addFavoriteStars, 0);
document.getElementById('onlineBankingContent')?.addEventListener('transitionend', addFavoriteStars);
document.getElementById('mobileBankingContent')?.addEventListener('transitionend', addFavoriteStars);
document.getElementById('mobileBankingContentMobile')?.addEventListener('transitionend', addFavoriteStars);
document.getElementById('onlineBankingContentMobile')?.addEventListener('transitionend', addFavoriteStars);

// Feedback modal
const feedbackBtn   = document.getElementById('feedbackBtn');
const feedbackModal = new bootstrap.Modal(document.getElementById('feedbackModal'));
const feedbackFullscreen = document.getElementById('feedbackFullscreen');
const closeFeedbackBtn = document.getElementById('closeFeedbackFullscreen');

const COOLDOWN_MS   = 15000;
const MIN_OPEN_TIME = 15000;
const ORIGINAL_TXT  = feedbackBtn.textContent.trim();

let cooldownTimer = null;
let modalOpenTime = null;
let minTimeTimer = null;
let shouldCooldown = false;

// Check if mobile (screen width <= 600px)
function isMobile() {
  return window.innerWidth <= 600;
}

feedbackBtn.addEventListener('click', () => {
  if (feedbackBtn.disabled) return;
  
  if (isMobile()) {
    // Show fullscreen overlay on mobile
    feedbackFullscreen.style.display = 'block';
    document.body.style.overflow = 'hidden';
    modalOpenTime = Date.now();
    shouldCooldown = false;
    minTimeTimer = setTimeout(() => { shouldCooldown = true; }, MIN_OPEN_TIME);
  } else {
    // Show modal on desktop
    feedbackModal.show();
  }
});

// Close fullscreen feedback
closeFeedbackBtn.addEventListener('click', () => {
  feedbackFullscreen.style.display = 'none';
  document.body.style.overflow = '';
  
  if (minTimeTimer) { clearTimeout(minTimeTimer); minTimeTimer = null; }
  if (shouldCooldown) {
    startCooldown();
  }
  modalOpenTime = null;
  shouldCooldown = false;
});

document.getElementById('feedbackModal').addEventListener('shown.bs.modal', () => {
  modalOpenTime = Date.now();
  shouldCooldown = false;
  minTimeTimer = setTimeout(() => { shouldCooldown = true; }, MIN_OPEN_TIME);
});

document.getElementById('feedbackModal').addEventListener('hidden.bs.modal', () => {
  if (minTimeTimer) { clearTimeout(minTimeTimer); minTimeTimer = null; }
  if (shouldCooldown) {
    startCooldown();
  }
  modalOpenTime = null;
  shouldCooldown = false;
});

function startCooldown() {
  if (cooldownTimer) clearTimeout(cooldownTimer);
  feedbackBtn.disabled = true;
  feedbackBtn.textContent = 'Feedback Sent!';
  cooldownTimer = setTimeout(() => {
    feedbackBtn.disabled = false;
    feedbackBtn.textContent = ORIGINAL_TXT;
    cooldownTimer = null;
  }, COOLDOWN_MS);
}
