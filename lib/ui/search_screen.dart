import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../data/repository.dart';
import '../services.dart';
import 'launch.dart';
import 'widgets/common.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.active});
  final bool active;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  SearchResults? _results;
  String _query = '';

  @override
  void didUpdateWidget(SearchScreen old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _focus.requestFocus();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () {
      final s = AppScope.of(context);
      final src = s.activeSource;
      if (src == null) return;
      final trimmed = q.trim();
      setState(() {
        _query = trimmed;
        _results = trimmed.length < 2 ? null : s.repo.search(src.id, trimmed);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final r = _results;
    return ListView(
      padding: const EdgeInsets.only(top: 24, bottom: 48),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 48),
          child: Text('Recherche', style: displayStyle(30)),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 48),
          child: TextField(
            controller: _controller,
            focusNode: _focus,
            onChanged: _onChanged,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            cursorColor: AppColors.accent,
            decoration: InputDecoration(
              hintText: 'Chaînes, films, séries…',
              prefixIcon: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14),
                child: Icon(Icons.search_rounded, size: 26, color: AppColors.accent),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 22),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: const BorderSide(color: AppColors.borderStrong),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
              ),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _controller.clear();
                        _onChanged('');
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 28),
        if (r == null)
          const EmptyState(
            icon: Icons.manage_search_rounded,
            title: 'Que veux-tu regarder ?',
            message: 'La recherche ignore les accents et la casse. Tape au moins 2 caractères.',
          )
        else if (r.isEmpty)
          EmptyState(icon: Icons.search_off_rounded, title: 'Aucun résultat pour « $_query »')
        else ...[
          if (r.channels.isNotEmpty) ...[
            SectionRow(
              title: 'Chaînes (${r.channels.length})',
              height: 88,
              itemCount: r.channels.length,
              itemBuilder: (context, i) {
                final c = r.channels[i];
                return HoverBuilder(
                  builder: (context, hover) => GestureDetector(
                    onTap: () => Launch.channel(context, c, r.channels),
                    child: Container(
                      width: 280,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: hover ? AppColors.surface2 : AppColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: hover ? AppColors.accent : AppColors.border),
                      ),
                      child: Row(
                        children: [
                          ChannelLogo(name: c.name, url: c.logo, size: 48),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              c.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 28),
          ],
          if (r.movies.isNotEmpty) ...[
            SectionRow(
              title: 'Films (${r.movies.length})',
              height: 300,
              itemCount: r.movies.length,
              itemBuilder: (context, i) {
                final m = r.movies[i];
                return PosterCard(
                  title: m.name,
                  subtitle: m.year?.toString(),
                  image: m.poster,
                  rating: m.rating,
                  onTap: () => Launch.openMovie(context, m),
                );
              },
            ),
            const SizedBox(height: 28),
          ],
          if (r.series.isNotEmpty)
            SectionRow(
              title: 'Séries (${r.series.length})',
              height: 300,
              itemCount: r.series.length,
              itemBuilder: (context, i) {
                final sr = r.series[i];
                return PosterCard(
                  title: sr.name,
                  subtitle: sr.year?.toString(),
                  image: sr.poster,
                  rating: sr.rating,
                  onTap: () => Launch.openSeries(context, sr),
                );
              },
            ),
        ],
      ],
    );
  }
}
