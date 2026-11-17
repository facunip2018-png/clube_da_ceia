'use client';

import Script from 'next/script';
import { useEffect, useRef, useState } from 'react';
import { AlertCircle, Play, Radio } from 'lucide-react';

type HlsInstance = {
  loadSource: (url: string) => void;
  attachMedia: (media: HTMLVideoElement) => void;
  destroy: () => void;
  on: (event: string, callback: (_event: string, data: { fatal?: boolean }) => void) => void;
};
type HlsConstructor = {
  new (): HlsInstance;
  isSupported: () => boolean;
  Events: { ERROR: string };
};
declare global { interface Window { Hls?: HlsConstructor } }

export function VideoPlayer({ hlsUrl, mp4Url, poster, title }: {
  hlsUrl: string | null;
  mp4Url: string | null;
  poster?: string | null;
  title: string;
}) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const [source, setSource] = useState<'hls' | 'mp4'>(hlsUrl ? 'hls' : 'mp4');
  const [engineReady, setEngineReady] = useState(false);
  const [engineFailed, setEngineFailed] = useState(false);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const activeUrl = source === 'hls' ? hlsUrl : mp4Url;

  useEffect(() => {
    const media = videoRef.current;
    if (!media || !activeUrl) return;
    setError('');
    media.pause();
    media.removeAttribute('src');
    media.load();

    if (source === 'mp4') {
      media.src = activeUrl;
      media.load();
      return;
    }
    if (media.canPlayType('application/vnd.apple.mpegurl')) {
      media.src = activeUrl;
      media.load();
      return;
    }

    const Hls = window.Hls;
    if (!Hls) {
      if (engineReady || engineFailed) {
        if (mp4Url) {
          setSource('mp4');
          setNotice('Este navegador não carregou o mecanismo HLS. O player mudou para a versão MP4.');
        } else {
          setError('Este navegador não reproduz HLS diretamente e o mecanismo de reprodução não foi carregado. Cadastre também a URL MP4 no painel.');
        }
      }
      return;
    }
    if (!Hls.isSupported()) {
      if (mp4Url) {
        setSource('mp4');
        setNotice('HLS não é compatível com este navegador. Reproduzindo a versão MP4.');
      } else {
        setError('HLS não é compatível com este navegador. Cadastre também uma URL MP4 para oferecer uma alternativa.');
      }
      return;
    }

    const player = new Hls();
    player.loadSource(activeUrl);
    player.attachMedia(media);
    player.on(Hls.Events.ERROR, (_event, data) => {
      if (!data.fatal) return;
      player.destroy();
      if (mp4Url) {
        setSource('mp4');
        setNotice('O fluxo HLS apresentou uma falha. O player mudou para a versão MP4.');
      } else {
        setError('Não foi possível reproduzir este vídeo HLS. Confira o link no painel Gumlet ou cadastre uma versão MP4.');
      }
    });
    return () => player.destroy();
  }, [activeUrl, source, mp4Url, engineReady, engineFailed]);

  return (
    <div className="gumlet-player">
      <Script src="https://cdn.jsdelivr.net/npm/hls.js@1.6.15/dist/hls.min.js" strategy="afterInteractive" onReady={() => setEngineReady(true)} onError={() => setEngineFailed(true)} />
      <div className="gumlet-player-screen">
        <video ref={videoRef} controls playsInline preload="metadata" poster={poster || undefined} aria-label={title} />
        {!activeUrl && <div className="gumlet-player-empty"><Play aria-hidden /><span>Adicione um link HLS ou MP4 para reproduzir.</span></div>}
      </div>
      <div className="gumlet-player-controls">
        <span className="gumlet-player-label"><Radio size={15} /> Player Gumlet</span>
        <div className="row">
          {hlsUrl && <button type="button" className={source === 'hls' ? 'gumlet-source active' : 'gumlet-source'} onClick={() => { setNotice(''); setSource('hls'); }}>HLS</button>}
          {mp4Url && <button type="button" className={source === 'mp4' ? 'gumlet-source active' : 'gumlet-source'} onClick={() => { setNotice(''); setSource('mp4'); }}>MP4</button>}
        </div>
      </div>
      {notice && <p className="gumlet-player-notice">{notice}</p>}
      {error && <p className="gumlet-player-error"><AlertCircle size={16} /> {error}</p>}
    </div>
  );
}
