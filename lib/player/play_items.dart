import '../data/models.dart';
import '../data/stream_urls.dart';
import 'player_service.dart';

PlayItem channelItem(Source s, Channel c) => PlayItem(
      kind: ContentKind.live,
      sourceId: s.id,
      extId: c.extId,
      url: StreamUrls.live(s, c),
      title: c.name,
      image: c.logo,
      userAgent: s.userAgent,
    );

PlayItem movieItem(Source s, Movie m, {String? image}) => PlayItem(
      kind: ContentKind.movie,
      sourceId: s.id,
      extId: m.extId,
      url: StreamUrls.movie(s, m),
      title: m.name,
      subtitle: m.year?.toString(),
      image: image ?? m.poster,
      userAgent: s.userAgent,
    );

PlayItem episodeItem(Source s, Series? series, Episode e) => PlayItem(
      kind: ContentKind.episode,
      sourceId: s.id,
      extId: e.extId,
      url: StreamUrls.episode(s, e),
      title: series?.name ?? e.displayTitle,
      subtitle: '${e.code} · ${e.displayTitle}',
      image: e.image ?? series?.backdrop ?? series?.poster,
      userAgent: s.userAgent,
      seriesExt: e.seriesExt,
    );
