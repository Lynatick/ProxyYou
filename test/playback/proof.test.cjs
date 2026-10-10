const test = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const script = fs.readFileSync('assets/playback/proof.js', 'utf8');
function setup() {
  let now = 0, ad = false;
  const video = {currentTime: 0, currentSrc:'blob:youtube', paused:false, ended:false, seeking:false,
    readyState:4, videoWidth:640, videoHeight:360, playbackRate:1, frames:0,
    getVideoPlaybackQuality(){return {totalVideoFrames:this.frames,droppedVideoFrames:0}}};
  const context = vm.createContext({URL, Number, Math, window:{__proxyyouExpectedId:'jNQXAC9IVRw'},
    location:{href:'https://www.youtube.com/watch?v=jNQXAC9IVRw',hostname:'www.youtube.com'},
    performance:{now:()=>now*1000}, document:{querySelector:s=>s==='video'?video:ad?{}:null}});
  const tick=(seconds=.5,frames=15)=>{now+=.5;video.currentTime+=seconds;video.frames+=frames;return vm.runInContext(script,context)};
  vm.runInContext(script,context);
  return {video, context, tick, setAd:v=>ad=v};
}
test('success requires five seconds and progressing decoded frames',()=>{
  const s=setup(); for(let i=0;i<9;i++) assert.equal(s.tick().status,'waiting');
  const result=s.tick(); assert.equal(result.status,'passed'); assert.equal(result.seconds,5); assert.equal(result.frames,150);
});
test('clock advancement without decoded frames cannot pass',()=>{const s=setup();for(let i=0;i<20;i++) assert.notEqual(s.tick(.5,0).status,'passed')});
test('stalled playback cannot pass even when frames increase',()=>{const s=setup();for(let i=0;i<20;i++) assert.notEqual(s.tick(0,15).status,'passed')});
test('seek jumps reset the proof',()=>{const s=setup();for(let i=0;i<9;i++)s.tick();assert.equal(s.tick(20).seconds,0)});
test('paused video resets accumulated progress',()=>{const s=setup();for(let i=0;i<9;i++)s.tick();s.video.paused=true;assert.equal(s.tick().seconds,0)});
test('ads cannot confirm the requested video',()=>{const s=setup();s.setAd(true);for(let i=0;i<20;i++) assert.notEqual(s.tick().status,'passed')});
test('another video cannot inherit the proof',()=>{const s=setup();for(let i=0;i<9;i++)s.tick();s.context.location.href='https://www.youtube.com/watch?v=abcdefghijk';assert.equal(s.tick().status,'waiting')});
test('source changes reset the proof',()=>{const s=setup();for(let i=0;i<9;i++)s.tick();s.video.currentSrc='blob:new';assert.equal(s.tick().status,'waiting');assert.notEqual(s.tick().status,'passed')});
test('absent frame counters are unsupported',()=>{const s=setup();s.video.getVideoPlaybackQuality=undefined;assert.equal(s.tick().status,'unsupported')});
test('dropped frames do not count as displayed frames',()=>{const s=setup();s.video.getVideoPlaybackQuality=function(){return {totalVideoFrames:this.frames,droppedVideoFrames:this.frames}};for(let i=0;i<20;i++)assert.notEqual(s.tick().status,'passed')});
