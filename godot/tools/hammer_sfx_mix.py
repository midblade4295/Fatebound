# The 0.30.7 hammer-throw mix (see SIEGE_PROGRESS.md). Inputs: whooshA.wav, whooshB.wav, spin2.wav (ElevenLabs SFX takes, 44.1 kHz mono).
import numpy as np, wave
from scipy import signal
SR=44100
def load(n):
    w=wave.open(n+".wav"); return np.frombuffer(w.readframes(w.getnframes()),dtype=np.int16).astype(np.float64)/32768
def save(n,x):
    w=wave.open(n,"wb"); w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes((np.clip(x,-1,1)*32767).astype(np.int16).tobytes()); w.close()
def filt(x,kind,f,order=4):
    sos=signal.butter(order,f,btype=kind,fs=SR,output="sos"); return signal.sosfilt(sos,x)
def place(buf,x,t,g=1.0):
    i=int(t*SR); n=min(len(x),len(buf)-i); buf[i:i+n]+=x[:n]*g
def env_ad(n,att,dec):
    t=np.arange(n)/SR; return np.minimum(1,t/att)*np.exp(-np.maximum(0,t-att)/dec)
def doppler(x,semis):
    # pitch falls smoothly by `semis` over the clip: variable-rate read
    n=len(x); rate=2**(-semis*np.linspace(0,1,n)/12); pos=np.cumsum(rate); pos=pos[pos<n-1]
    return np.interp(pos,np.arange(n),x)
def sat(x,drive):
    return np.tanh(x*drive)/np.tanh(drive)
def build(heavy):
    L=1.25; out=np.zeros(int(SR*L))
    A=load("whooshA"); B=load("whooshB"); S=load("spin2")
    # 1. the punch: whoosh B, saturated so its bass grows harmonics a phone speaker can play
    b=sat(filt(B,"highpass",45),2.2); b=b*env_ad(len(b),0.004,0.32 if heavy else 0.22)
    place(out,b,0.0,0.85)
    # 2. the body: whoosh A (its swell trimmed so it peaks just behind B's attack: a thick double hit)
    a=A[int(0.06*SR):]; a=sat(filt(a,"lowpass",1400),2.8 if heavy else 2.0); a=filt(a,"highpass",45)
    a=a*env_ad(len(a),0.02,0.42 if heavy else 0.28)
    place(out,a,0.012,0.75 if heavy else 0.55)
    # 3. the air: a noise swish sweeping down, pulsing at the hammer's spin rate (none of the takes had any highs)
    n=int(SR*0.9); rng=np.random.default_rng(3); z=rng.standard_normal(n)
    sw=np.zeros(n); blk=1024
    for k in range(0,n,blk):
        fc=6500*(1500/6500)**(k/n)          # 6.5 kHz -> 1.5 kHz
        seg=z[max(0,k-2048):k+blk]; y=filt(seg,"bandpass",[fc*0.6,min(fc*1.6,20000)],2)
        sw[k:k+blk]=y[-len(z[k:k+blk]):]
    spin_hz=11.0 if heavy else 13.0
    am=1-0.55*(0.5+0.5*np.cos(2*np.pi*spin_hz*np.arange(n)/SR))
    sw=sw/np.abs(sw).max()*am*env_ad(n,0.035,0.30 if heavy else 0.36)
    place(out,sw,0.02,0.30 if heavy else 0.42)
    # 4. the spin: take 2, its pitch falling as the hammer flies off, a little saturation
    s=doppler(S,3.0 if heavy else 4.0); s=sat(filt(s,"highpass",120),1.6)
    s=s*env_ad(len(s),0.03,0.35)
    place(out,s,0.07,0.95)
    # bus: glue, keep phone-useless sub in check, short tail fade, peak to the game's 0.56
    out=filt(out,"highpass",55,2)
    out=sat(out/np.abs(out).max(),1.8)
    fade=np.ones(len(out)); fn=int(0.18*SR); fade[-fn:]=np.linspace(1,0,fn)**2; out*=fade
    return out/np.abs(out).max()*0.56
for name,heavy in [("hammerThrow_heavy",True),("hammerThrow_punchy",False)]:
    x=build(heavy); save(name+".wav",x)
    spec=np.abs(np.fft.rfft(x)); f=np.fft.rfftfreq(len(x),1/SR)
    bands=[(20,120),(120,400),(400,1500),(1500,5000),(5000,16000)]
    bp=[(spec[(f>=a)&(f<b)]**2).sum()/(spec**2).sum()*100 for a,b in bands]
    hop=int(SR*0.05); env=[20*np.log10(np.sqrt(np.mean(x[i:i+hop]**2))+1e-9) for i in range(0,len(x),hop)]
    print(name,"len %.2f rms %.3f bands(sub,low,mid,hi,air)%%: %s"%(len(x)/SR,np.sqrt(np.mean(x**2))," ".join("%.0f"%v for v in bp)))
    print("   env50ms:"," ".join("%d"%v for v in env))
