(() => {
  const expected = window.__proxyyouExpectedId;
  const id = new URL(location.href).searchParams.get('v');
  const validPage = /^(www\.|m\.)?youtube\.com$/.test(location.hostname) && id === expected;
  const video = document.querySelector('video');
  if (!validPage || !video) { window.__proxyyouProof = null; return {status: 'waiting'}; }
  const quality = typeof video.getVideoPlaybackQuality === 'function' ? video.getVideoPlaybackQuality() : null;
  const frames = quality ? quality.totalVideoFrames - quality.droppedVideoFrames : video.webkitDecodedFrameCount;
  if (!Number.isFinite(frames)) return {status: 'unsupported'};
  const now = performance.now() / 1000;
  let state = window.__proxyyouProof;
  const source = video.currentSrc;
  if (!state || state.video !== video || state.source !== source) {
    state = {video, source, time: video.currentTime, frames, now, seconds: 0, decoded: 0};
    window.__proxyyouProof = state;
    return {status: 'waiting'};
  }
  const delta = video.currentTime - state.time;
  const wall = now - state.now;
  const rendered = frames - state.frames;
  const ad = document.querySelector('.ad-showing, .ad-interrupting');
  const progressing = !ad && !video.paused && !video.ended && !video.seeking && video.readyState >= 2 &&
    video.videoWidth > 0 && video.videoHeight > 0 && video.playbackRate === 1 &&
    delta > 0 && delta < 1.5 && wall > 0 && wall < 1.5 && Math.abs(delta - wall) < 0.65 && rendered > 0;
  if (progressing) { state.seconds += Math.min(delta, wall); state.decoded += rendered; }
  else { state.seconds = 0; state.decoded = 0; }
  state.time = video.currentTime; state.frames = frames; state.now = now;
  return {status: state.seconds >= 5 && state.decoded >= 10 ? 'passed' : 'waiting',
    seconds: state.seconds, frames: state.decoded, videoId: id};
})()
