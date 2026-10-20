const METADATA_TIMEOUT_MS = 5000;

export function cameraSupports(videoEl) {
  void videoEl;
  return !!(typeof navigator !== 'undefined'
    && navigator.mediaDevices
    && typeof navigator.mediaDevices.getUserMedia === 'function');
}

function waitMetadata(videoEl) {
  return new Promise((resolve, reject) => {
    if (videoEl.readyState >= 1 && videoEl.videoWidth > 0) {
      resolve();
      return;
    }
    let done = false;
    const finish = (err) => {
      if (done) return;
      done = true;
      videoEl.removeEventListener('loadedmetadata', ok);
      clearTimeout(timer);
      if (err) reject(err);
      else resolve();
    };
    const ok = () => finish(null);
    const timer = setTimeout(() => {
      finish(new Error('Camera preview timed out after 5 seconds. Close other apps using the camera, then tap Start again.'));
    }, METADATA_TIMEOUT_MS);
    videoEl.addEventListener('loadedmetadata', ok, { once: true });
  });
}

function describeTrack(track, fallbackFacing) {
  if (!track || typeof track.getSettings !== 'function') {
    return { facingMode: fallbackFacing, width: 0, height: 0, deviceId: '' };
  }
  const s = track.getSettings();
  return {
    facingMode: s.facingMode || fallbackFacing,
    width: s.width || 0,
    height: s.height || 0,
    deviceId: s.deviceId || '',
  };
}

export async function openCamera(videoEl, opts = {}) {
  const { facing = 'environment', deviceId = null, width = 1280, height = 720 } = opts;

  if (!videoEl) throw new Error('No video element to attach the camera to.');
  if (!cameraSupports(videoEl)) {
    const err = new Error('This browser cannot open a camera.');
    err.name = 'NotSupportedError';
    throw err;
  }

  const video = {
    facingMode: deviceId ? undefined : facing,
    width: { ideal: width },
    height: { ideal: height },
    frameRate: { ideal: 30 },
  };
  if (deviceId) video.deviceId = { exact: deviceId };

  const stream = await navigator.mediaDevices.getUserMedia({ video, audio: false });

  videoEl.setAttribute('playsinline', '');
  videoEl.setAttribute('webkit-playsinline', '');
  videoEl.muted = true;
  videoEl.srcObject = stream;

  await waitMetadata(videoEl);

  const track = stream.getVideoTracks()[0];
  const info = describeTrack(track, facing);
  const settings = {
    facingMode: info.facingMode,
    width: info.width,
    height: info.height,
    deviceId: info.deviceId,
    facing: info.facingMode === 'user' ? 'user' : facing,
    needsTap: false,
  };

  try {
    await videoEl.play();
  } catch (err) {
    void err;
    settings.needsTap = true;
  }

  return { stream, settings, track, videoEl };
}

export async function closeCamera(state) {
  if (!state) return;
  try {
    const stream = state.stream;
    if (stream && typeof stream.getTracks === 'function') {
      for (const track of stream.getTracks()) {
        try { track.stop(); } catch (err) { void err; }
      }
    }
    if (state.videoEl) state.videoEl.srcObject = null;
  } catch (err) {
    void err;
  }
}

export async function resumePreview(videoEl) {
  if (!videoEl) return false;
  try {
    await videoEl.play();
    return true;
  } catch (err) {
    void err;
    return false;
  }
}

export async function switchCamera(videoEl, facing, state) {
  await closeCamera(state);
  return openCamera(videoEl, { facing, deviceId: null });
}

export async function listCameras() {
  try {
    if (!cameraSupports(null)) return [];
    const devices = await navigator.mediaDevices.enumerateDevices();
    return devices
      .filter((d) => d.kind === 'videoinput')
      .map((d, i) => ({
        deviceId: d.deviceId,
        label: d.label || `Camera ${i + 1}`,
        kind: d.kind,
      }));
  } catch (err) {
    void err;
    return [];
  }
}

export function describeCameraError(err) {
  const name = (err && err.name) || '';
  const message = (err && err.message) || '';

  if (typeof window !== 'undefined' && window.isSecureContext === false) {
    return {
      title: 'The camera needs a secure (HTTPS) address',
      steps: [
        'iOS and macOS block the camera on plain http:// pages, and on any address other than localhost.',
        'Open the app through its https:// address, or tap the Share button in Safari and choose Add to Home Screen so it loads over HTTPS.',
        'If you are testing on your own machine, use https://localhost or a TLS tunnel, then reload.',
      ],
    };
  }

  switch (name) {
    case 'NotAllowedError':
    case 'PermissionDeniedError':
      return {
        title: 'Camera permission was blocked',
        steps: [
          'Tap the camera or page-info icon in the address bar and set Camera to Allow, then reload.',
          'If it still says blocked: Settings ▸ Safari ▸ Camera ▸ Allow (or "Ask"), then scroll back to the app.',
          'For a home-screen app: Settings ▸ pushups ▸ Camera ▸ Allow.',
          'Close other apps that may hold the camera (Photo Booth, FaceTime) and tap Start again.',
        ],
      };
    case 'NotFoundError':
    case 'DevicesNotFoundError':
      return {
        title: 'No camera found for this choice',
        steps: [
          'The selected camera is gone (headset, external cam, or a back/front switch on a device with one camera).',
          'Open Settings in the app and pick the other camera, or reload the page to re-list cameras.',
        ],
      };
    case 'NotReadableError':
    case 'InUseError':
    case 'TrackStartError':
      return {
        title: 'Another app or tab is using the camera',
        steps: [
          'Close the other browser tab that has the camera open.',
          'Quit any app recording video, then relaunch the app from the Home Screen.',
          'If it keeps happening, restart the iPhone: the camera service on iOS sometimes stays locked.',
        ],
      };
    case 'OverconstrainedError':
      return {
        title: 'The camera cannot do the settings we asked for',
        steps: [
          'Lower the resolution in Settings (try 640 x 480) or switch facing mode.',
          'Tap Start again.',
        ],
      };
    case 'SecurityError':
      return {
        title: 'The browser blocked camera access for security',
        steps: [
          'Confirm the page address starts with https:// (or localhost).',
          'Reload the page.',
          'If the app came from a Home Screen icon, delete it and add it again from the https:// page.',
        ],
      };
    case 'NotSupportedError':
      return {
        title: 'This browser has no camera access',
        steps: [
          'Open the app in Safari (Chrome and in-app browsers on iOS cannot always reach the camera).',
          'Update iOS to the current release, then reload.',
        ],
      };
    case 'AbortError':
      return {
        title: 'Camera start was interrupted',
        steps: ['Tap Start again.', 'If it repeats, close other camera apps and reload.'],
      };
    default:
      return {
        title: 'The camera did not open',
        steps: [
          message ? `Details: ${message}` : 'No details from the browser.',
          'Tap Start again.',
          'Reload the page, then check Settings ▸ Safari ▸ Camera ▸ Allow.',
        ],
      };
  }
}

export async function setTorch(track, on) {
  if (!track || typeof track.applyConstraints !== 'function') return false;
  try {
    const caps = typeof track.getCapabilities === 'function' ? track.getCapabilities() : null;
    if (!caps || !caps.torch) return false;
    await track.applyConstraints({ advanced: [{ torch: !!on }] });
    if (!on) await track.applyConstraints({ advanced: [{}] });
    return true;
  } catch (err) {
    void err;
    return false;
  }
}
