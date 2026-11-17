'use client';

import { useTable } from '@/data/hooks';
import { Guard } from '@/components/gates';
import { Empty, Loading, PageHead } from '@/components/ui';
import { VideoPlayer } from '@/components/video-player';
import { Clapperboard, Video as VideoIcon } from 'lucide-react';

export default function VideosPage() {
  const { rows: videos, loading } = useTable('videos', { eq: { status: 'published' }, order: [['position', 'asc'], ['created_at', 'desc']] });
  const { rows: collections } = useTable('collections');
  const { rows: recipes } = useTable('recipes');
  return (
    <Guard access what="A biblioteca de vídeos">
      <PageHead eyebrow="Aulas e demonstrações" title="Vídeos do Clube." sub="Assista às aulas e demonstrações organizadas para acompanhar suas receitas." />
      {loading || !videos || !collections || !recipes ? <Loading /> : videos.length ? (
        <div className="video-library-grid">
          {videos.map((video) => {
            const collection = collections.find((item) => item.id === video.collection_id);
            const recipe = recipes.find((item) => item.id === video.recipe_id);
            return (
              <article key={video.id} className="video-library-card">
                <VideoPlayer hlsUrl={video.hls_url} mp4Url={video.mp4_url} poster={video.thumbnail_url} title={video.title} />
                <div className="video-library-copy">
                  <div className="eyebrow"><Clapperboard size={13} /> Vídeo do Clube</div>
                  <h2>{video.title}</h2>
                  {video.description && <p className="sub">{video.description}</p>}
                  <div className="row">
                    {collection && <span className="pill">{collection.name}</span>}
                    {recipe && <span className="pill gold">{recipe.title}</span>}
                    {video.duration_seconds && <span className="pill muted">{Math.floor(video.duration_seconds / 60)} min</span>}
                  </div>
                </div>
              </article>
            );
          })}
        </div>
      ) : <Empty icon={VideoIcon} title="Novos vídeos em breve">Quando novos vídeos forem publicados, eles aparecerão aqui.</Empty>}
    </Guard>
  );
}
