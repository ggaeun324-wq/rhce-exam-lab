const host = window.location.hostname;
const termWrap = document.getElementById("terminals");
const panels = [...document.querySelectorAll(".panel")];
const hostLabel = document.getElementById("hostlabel");
const frames = {};

const TERMS = {
  foundation: { port: 7710, label: "● foundation (외부 터미널) — 여기서 <code>ssh greg@control</code> 로 시작", debug: false },
  control:    { port: 7701, label: "● control node — control.lab.example.com (192.168.59.130) · greg", debug: false },
  node1: { port: 7702, label: "node1 (root 콘솔·디버그)", debug: true },
  node2: { port: 7703, label: "node2 (root 콘솔·디버그)", debug: true },
  node3: { port: 7704, label: "node3 (root 콘솔·디버그)", debug: true },
  node4: { port: 7705, label: "node4 (root 콘솔·디버그)", debug: true },
  node5: { port: 7706, label: "node5 (root 콘솔·디버그)", debug: true },
  repo:  { port: 7700, label: "repo/materials 서버 (root 콘솔·디버그)", debug: true },
};

function makeFrame(name, port) {
  if (frames[name]) return frames[name];
  const f = document.createElement("iframe");
  f.src = `http://${host}:${port}`;
  frames[name] = f;
  termWrap.appendChild(f);
  return f;
}

function showTerminal(name) {
  const t = TERMS[name];
  if (!t) return;
  panels.forEach(p => p.classList.remove("active"));   // 오버레이 닫고 터미널 표시
  const f = makeFrame(name, t.port);
  Object.values(frames).forEach(fr => fr.classList.remove("active"));
  f.classList.add("active");
  hostLabel.innerHTML = t.label;
  hostLabel.classList.toggle("debug", !!t.debug);
  document.querySelectorAll(".term-btn").forEach(b =>
    b.classList.toggle("primary", b.dataset.term === name));
}

// 터미널 전환 버튼
document.querySelectorAll(".term-btn").forEach(b => {
  b.addEventListener("click", () => showTerminal(b.dataset.term));
});

// 오른쪽 오버레이 패널 (구성도/시작절차/채점)
document.querySelectorAll("header button[data-panel]").forEach(b => {
  b.addEventListener("click", () => {
    const p = document.getElementById("panel-" + b.dataset.panel);
    const isActive = p.classList.contains("active");
    panels.forEach(x => x.classList.remove("active"));
    if (!isActive) p.classList.add("active");
  });
});

// 왼쪽 문제 도크 토글
const dock = document.getElementById("qdock");
const dragbar = document.getElementById("dragbar");
const dockbtn = document.getElementById("dockbtn");
function setDock(open) {
  dock.classList.toggle("open", open);
  dragbar.style.display = open ? "block" : "none";
  dockbtn.classList.toggle("primary", open);
}
dockbtn.addEventListener("click", () => setDock(!dock.classList.contains("open")));
document.getElementById("qclose").addEventListener("click", () => setDock(false));

// 모두 펼치기/접기
let allOpen = false;
document.getElementById("qexpand").addEventListener("click", () => {
  allOpen = !allOpen;
  document.querySelectorAll(".qcard").forEach(c => c.open = allOpen);
});

// 드래그로 도크 폭 조절
(function () {
  let dragging = false;
  dragbar.addEventListener("mousedown", e => { dragging = true; document.body.style.userSelect = "none"; e.preventDefault(); });
  window.addEventListener("mousemove", e => {
    if (!dragging) return;
    const w = Math.min(Math.max(e.clientX, 280), Math.min(760, window.innerWidth - 320));
    dock.style.width = w + "px";
  });
  window.addEventListener("mouseup", () => { dragging = false; document.body.style.userSelect = ""; });
})();

// 디버그 콘솔 드롭다운
const dbgbtn = document.getElementById("dbgbtn");
const dbgmenu = document.getElementById("dbgmenu");
dbgbtn.addEventListener("click", e => { e.stopPropagation(); dbgmenu.classList.toggle("open"); });
document.addEventListener("click", () => dbgmenu.classList.remove("open"));
dbgmenu.querySelectorAll("a").forEach(a => {
  a.addEventListener("click", () => { showTerminal(a.dataset.term); dbgmenu.classList.remove("open"); });
});

// 문제 카드 렌더링
(function renderQuestions() {
  const box = document.getElementById("qlist");
  const qs = window.RHCE_QUESTIONS || [];
  if (!qs.length) { box.textContent = "문제 데이터를 불러오지 못했습니다."; return; }
  const doneSet = JSON.parse(localStorage.getItem("rhce_done") || "[]");
  const isDone = n => doneSet.includes(String(n));
  box.innerHTML = qs.map(q => `
    <details class="qcard${isDone(q.n) ? " done" : ""}" data-n="${q.n}">
      <summary>
        <button class="qcheck" data-n="${q.n}" title="완료 표시">${isDone(q.n) ? "✅" : "⬜"}</button>
        <span class="qnum">Q${q.n}</span> <span class="qtitle">${q.title}</span>
      </summary>
      <div class="qbody">
        <div class="qfile">📄 <code>${q.file}</code></div>
        ${q.desc ? `<p class="qdesc">${q.desc}</p>` : ""}
        <ul>${q.req.map(r => `<li>${r}</li>`).join("")}</ul>
        <div class="qtip">초기화하려면 control 터미널에서 <code>rhce-reset ${q.n}</code></div>
      </div>
    </details>`).join("");

  // 완료 체크 토글 (카드 펼침과 분리)
  box.querySelectorAll(".qcheck").forEach(btn => {
    btn.addEventListener("click", e => {
      e.preventDefault();
      e.stopPropagation();
      const n = String(btn.dataset.n);
      let set = JSON.parse(localStorage.getItem("rhce_done") || "[]");
      const card = btn.closest(".qcard");
      if (set.includes(n)) {
        set = set.filter(x => x !== n);
        btn.textContent = "⬜";
        card.classList.remove("done");
      } else {
        set.push(n);
        btn.textContent = "✅";
        card.classList.add("done");
      }
      localStorage.setItem("rhce_done", JSON.stringify(set));
      updateProgress();
    });
  });
  updateProgress();
})();

// 진행률 표시
function updateProgress() {
  const el = document.getElementById("qprogress");
  if (!el) return;
  const total = (window.RHCE_QUESTIONS || []).length;
  const done = JSON.parse(localStorage.getItem("rhce_done") || "[]").length;
  el.textContent = `${done}/${total} 완료`;
}

// 시작: 도크 열림 + 외부(foundation) 터미널
setDock(true);
showTerminal("foundation");
