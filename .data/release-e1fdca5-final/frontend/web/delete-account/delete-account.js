const params = new URLSearchParams(window.location.search);
const token = params.get('token') || '';
const requestForm = document.getElementById('request-form');
const requestStatus = document.getElementById('request-status');
const confirmSection = document.getElementById('confirm-section');
const confirmStatus = document.getElementById('confirm-status');
const confirmButton = document.getElementById('confirm-button');

function showStatus(element, message, isError) {
  element.textContent = message;
  element.classList.toggle('error', Boolean(isError));
  element.hidden = false;
}

if (token) {
  confirmSection.hidden = false;
  confirmSection.scrollIntoView();
}

requestForm.addEventListener('submit', async (event) => {
  event.preventDefault();
  const button = requestForm.querySelector('button');
  const email = requestForm.email.value.trim();
  button.disabled = true;
  requestStatus.hidden = true;
  try {
    const response = await fetch('/api/v1/users/account-deletion-requests', {
      method: 'POST',
      headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
      body: JSON.stringify({email}),
    });
    if (!response.ok) {
      throw new Error('request_failed');
    }
    showStatus(
      requestStatus,
      'If an active Mushukistan account exists for this email address, a confirmation link will be sent.',
      false,
    );
    requestForm.reset();
  } catch (_) {
    showStatus(requestStatus, 'The request could not be submitted. Please try again later.', true);
  } finally {
    button.disabled = false;
  }
});

confirmButton.addEventListener('click', async () => {
  confirmButton.disabled = true;
  confirmStatus.hidden = true;
  try {
    const response = await fetch('/api/v1/users/account-deletion-confirmations', {
      method: 'POST',
      headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
      body: JSON.stringify({token}),
    });
    if (!response.ok) {
      throw new Error('confirmation_failed');
    }
    showStatus(confirmStatus, 'Your Mushukistan account deletion has been confirmed.', false);
    confirmButton.hidden = true;
  } catch (_) {
    showStatus(confirmStatus, 'This confirmation link is invalid, expired, or can no longer be used.', true);
    confirmButton.disabled = false;
  }
});
