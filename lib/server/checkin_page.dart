/// 학생 폰에서 열리는 체크인 페이지. 외부 리소스를 참조하지 않는 자체 완결 HTML+JS 한 장이다.
///
/// 학원 로컬 네트워크는 인터넷이 끊겨 있을 수 있으므로 CDN·웹폰트·원격 이미지를 쓰면 안 된다.
/// 서버 주소도 박지 않는다 — 요청은 모두 같은 출처의 상대 경로로 보낸다.
///
/// 등원인지 하원인지는 페이지가 고르지 않는다. 스캔한 QR 의 종류가 세션에 담겨 오고,
/// 페이지는 그것을 제목으로 보여줄 뿐이다.
///
/// 원시 문자열(`r'''`)이므로 JS 의 `$` 가 Dart 보간으로 해석되지 않는다.
const String checkInPageHtml = r'''<!doctype html>
<html lang="ko">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>출결 체크</title>
<style>
  * { box-sizing: border-box; }
  body {
    margin: 0;
    padding: 24px 16px;
    font-family: sans-serif;
    font-size: 18px;
    line-height: 1.5;
    color: #222;
    background: #f4f5f7;
  }
  main { max-width: 420px; margin: 0 auto; }
  h1 { margin: 0 0 16px; font-size: 28px; text-align: center; }
  #message { margin: 16px 0; text-align: center; word-break: keep-all; }
  #message.ok { color: #1b7f3b; font-weight: bold; font-size: 22px; }
  #message.late { color: #b45309; }
  #message.error { color: #b3261e; }

  /* 체크가 끝났거나 막혔을 때는 화면 전체를 한 색으로 채운다. 멀리서 힐끗 봐도 결과를 알 수 있어야
     해서다. 초록 = 기록됨, 주황 = 지각으로 기록됨, 파랑 = 이미 기록돼 있음, 빨강 = 못 찍음. */
  #mark { display: none; text-align: center; font-size: 96px; line-height: 1.1; font-weight: bold; }
  body.state-ok, body.state-late, body.state-again, body.state-fail { color: #fff; }
  body.state-ok { background: #1b7f3b; }
  body.state-late { background: #b45309; }
  body.state-again { background: #2563eb; }
  body.state-fail { background: #b3261e; }
  body.state-ok #mark, body.state-late #mark, body.state-again #mark, body.state-fail #mark { display: block; }
  body.state-ok #message, body.state-late #message, body.state-again #message, body.state-fail #message {
    color: #fff; font-size: 26px; font-weight: bold;
  }
  .field { display: block; width: 100%; margin: 8px 0; padding: 14px; font-size: 18px; }
  button { display: block; width: 100%; margin: 8px 0; padding: 14px; font-size: 18px; border: 0; border-radius: 8px; color: #fff; background: #2563eb; }
  button.secondary { color: #222; background: #dfe3e8; }
  [hidden] { display: none !important; }
</style>
</head>
<body>
<main>
  <h1 id="title">출결 체크</h1>
  <div id="mark" aria-hidden="true"></div>
  <p id="message">확인하는 중입니다...</p>

  <section id="identify" hidden>
    <select id="memberSelect" class="field"></select>
    <input id="contactLast4" class="field" type="text" inputmode="numeric" pattern="[0-9]*" maxlength="4" autocomplete="off" placeholder="학부모 연락처 뒷 4자리">
    <input id="adminCode" class="field" type="text" inputmode="numeric" pattern="[0-9]*" maxlength="6" autocomplete="off" placeholder="관리자 발급 코드 (연락처가 없는 경우)">
    <button id="bindButton" type="button">확인</button>
  </section>

  <button id="switchButton" class="secondary" type="button" hidden>다른 사람으로 체크</button>
</main>
<script>
(function () {
  var titleEl = document.getElementById('title');
  var messageEl = document.getElementById('message');
  var identifyEl = document.getElementById('identify');
  var memberSelect = document.getElementById('memberSelect');
  var contactInput = document.getElementById('contactLast4');
  var adminCodeInput = document.getElementById('adminCode');
  var bindButton = document.getElementById('bindButton');
  var switchButton = document.getElementById('switchButton');

  var sessionId = null;
  var deviceToken = null;

  var markEl = document.getElementById('mark');

  // 결과에 따라 화면 전체의 색과 큰 표시를 바꾼다. state 가 없으면 평소 화면이다.
  var MARKS = { ok: '✓', late: '✓', again: '✓', fail: '✕' };
  function setState(state) {
    document.body.className = state ? 'state-' + state : '';
    markEl.textContent = state ? MARKS[state] : '';
  }

  function show(text, cls, state) {
    messageEl.textContent = text;
    messageEl.className = cls || '';
    setState(state);
  }

  // 더는 진행할 수 없는 오류. 양식 안의 입력 안내는 show(..., 'error') 로 인라인에 두고 화면은 그대로 둔다.
  function showError(text) {
    identifyEl.hidden = true;
    show(text, 'error', 'fail');
  }

  var EXPIRED = 'QR 코드가 만료되었습니다. 다시 스캔해 주세요.';
  var UNEXPECTED = '문제가 발생했습니다. 잠시 후 QR 코드를 다시 스캔해 주세요.';

  // 응답 본문이 JSON 이 아니어도(프록시 오류 등) 상태 코드만으로 분기할 수 있게 한다.
  function request(method, path, body) {
    var options = { method: method, cache: 'no-store' };
    if (body !== undefined) {
      options.headers = { 'Content-Type': 'application/json' };
      options.body = JSON.stringify(body);
    }
    return fetch(path, options).then(function (response) {
      return response.json().catch(function () { return {}; }).then(function (data) {
        return { status: response.status, data: data };
      });
    });
  }

  function getOrCreateDeviceToken() {
    var token = localStorage.getItem('deviceToken');
    if (!token) {
      var bytes = new Uint8Array(8);
      crypto.getRandomValues(bytes);
      token = Array.prototype.map.call(bytes, function (b) {
        return (b < 16 ? '0' : '') + b.toString(16);
      }).join('');
      localStorage.setItem('deviceToken', token);
    }
    return token;
  }

  // 1~2. QR 토큰으로 세션을 받고, 종류에 따라 제목을 정한다.
  function start() {
    var token = new URLSearchParams(location.search).get('token');
    if (!token) { showError(EXPIRED); return; }

    request('GET', '/api/session?token=' + encodeURIComponent(token)).then(function (r) {
      if (r.status === 403) { showError(EXPIRED); return; }
      if (r.status !== 200 || !r.data.sessionId) { showError(UNEXPECTED); return; }
      sessionId = r.data.sessionId;
      titleEl.textContent = r.data.kind === 'checkOut' ? '하원' : '등원';
      // 3. 기기 토큰
      deviceToken = getOrCreateDeviceToken();
      identify();
    }).catch(function () { showError(UNEXPECTED); });
  }

  // 4. 이 폰이 누구인지 확인한다. 묶여 있으면 곧바로 체크한다.
  function identify(afterSwitch) {
    request('GET', '/api/device-status?deviceToken=' + encodeURIComponent(deviceToken) +
        '&session=' + encodeURIComponent(sessionId)).then(function (r) {
      if (r.status === 403) { showSessionGone(afterSwitch); return; }
      if (r.status !== 200) { showError(UNEXPECTED); return; }
      if (r.data.bound) { checkIn(); return; }
      loadMembers(afterSwitch);
    }).catch(function () { showError(UNEXPECTED); });
  }

  // 체크가 끝난 세션은 다시 쓸 수 없다. "다른 사람으로 체크" 직후라면 그 사람이 새로 스캔하게 한다.
  function showSessionGone(afterSwitch) {
    switchButton.hidden = true;
    if (afterSwitch) {
      showError('이 폰의 기록을 지웠습니다. QR 코드를 다시 스캔하면 본인 확인부터 시작합니다.');
    } else {
      showError(EXPIRED);
    }
  }

  function loadMembers(afterSwitch) {
    request('GET', '/api/members?session=' + encodeURIComponent(sessionId)).then(function (r) {
      if (r.status === 403) { showSessionGone(afterSwitch); return; }
      if (r.status !== 200 || !Array.isArray(r.data)) { showError(UNEXPECTED); return; }
      if (r.data.length === 0) { showError('등록된 회원이 없습니다. 관리자에게 문의해 주세요.'); return; }

      memberSelect.textContent = '';
      var placeholder = document.createElement('option');
      placeholder.value = '';
      placeholder.textContent = '이름을 선택하세요';
      memberSelect.appendChild(placeholder);
      r.data.forEach(function (m) {
        var option = document.createElement('option');
        option.value = String(m.id);
        option.textContent = m.name;
        memberSelect.appendChild(option);
      });
      contactInput.value = '';
      adminCodeInput.value = '';
      identifyEl.hidden = false;
      switchButton.hidden = true;
      show('이름을 고르고 학부모 연락처 뒷 4자리를 입력해 주세요.');
    }).catch(function () { showError(UNEXPECTED); });
  }

  function bind() {
    var memberId = parseInt(memberSelect.value, 10);
    var last4 = contactInput.value.trim();
    var adminCode = adminCodeInput.value.trim();
    if (isNaN(memberId)) { show('이름을 선택해 주세요.', 'error'); return; }
    // 관리자 코드가 있으면 그것으로, 없으면 연락처 뒷 4자리로 확인한다.
    var payload = { session: sessionId, deviceToken: deviceToken, memberId: memberId };
    if (adminCode) {
      if (!/^[0-9]{6}$/.test(adminCode)) { show('관리자 코드는 숫자 6자리입니다.', 'error'); return; }
      payload.adminCode = adminCode;
    } else {
      if (!/^[0-9]{4}$/.test(last4)) { show('연락처 뒷 4자리를 숫자로 입력해 주세요.', 'error'); return; }
      payload.contactLast4 = last4;
    }

    bindButton.disabled = true;
    request('POST', '/api/bind', payload).then(function (r) {
      bindButton.disabled = false;
      if (r.status === 200 && r.data.bound) { identifyEl.hidden = true; checkIn(); return; }
      var error = r.data.error;
      if (error === 'verification_unavailable') { show('관리자에게 코드를 받아 입력해 주세요.', 'error'); return; }
      if (error === 'verification_failed') { show('연락처 또는 코드가 일치하지 않습니다.', 'error'); return; }
      if (error === 'too_many_attempts') { show('잠시 후 다시 시도해 주세요.', 'error'); return; }
      if (error === 'invalid_session') { showError(EXPIRED); return; }
      showError(UNEXPECTED);
    }).catch(function () { bindButton.disabled = false; showError(UNEXPECTED); });
  }

  // 5. 체크를 기록하고 결과를 그린다. 등원인지 하원인지는 서버가 세션으로 정한다.
  function checkIn() {
    request('POST', '/api/checkin', { session: sessionId, deviceToken: deviceToken }).then(function (r) {
      switchButton.hidden = false;
      var d = r.data;
      if (r.status === 200) {
        if (d.result === 'checkedIn') {
          show(d.memberName + ' 님 등원 완료' + (d.status === 'late' ? ' (지각)' : ''),
              d.status === 'late' ? 'ok late' : 'ok',
              d.status === 'late' ? 'late' : 'ok');
          return;
        }
        if (d.result === 'checkedOut') { show(d.memberName + ' 님 하원 완료', 'ok', 'ok'); return; }
        if (d.result === 'alreadyCheckedIn') { show('이미 등원하셨습니다', 'ok', 'again'); return; }
        if (d.result === 'alreadyCheckedOut') { show('오늘은 이미 하원 처리되었습니다', 'ok', 'again'); return; }
        showError(UNEXPECTED);
        return;
      }
      if (d.error === 'no_open_session') { showError('등원 기록이 없습니다'); return; }
      // 이 기기가 (더는) 어떤 회원에도 묶여 있지 않다 — 본인 확인부터 다시 거친다.
      if (d.error === 'member_required') { switchButton.hidden = true; loadMembers(false); return; }
      if (d.error === 'invalid_session') { showError(EXPIRED); return; }
      showError(UNEXPECTED);
    }).catch(function () { showError(UNEXPECTED); });
  }

  // 6. 폰을 여러 명이 쓰는 경우: 기기 토큰을 지우고 본인 확인을 다시 거친다.
  function switchPerson() {
    localStorage.removeItem('deviceToken');
    deviceToken = getOrCreateDeviceToken();
    switchButton.hidden = true;
    show('확인하는 중입니다...');
    identify(true);
  }

  bindButton.addEventListener('click', bind);
  switchButton.addEventListener('click', switchPerson);
  start();
})();
</script>
</body>
</html>
''';
