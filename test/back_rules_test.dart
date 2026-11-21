import 'package:bobine/ui/back_rules.dart';
import 'package:bobine/ui/shell.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Retour depuis les onglets', () {
    test('la recherche ouverte se ferme d’abord, même depuis l’accueil', () {
      expect(shellBack(searchOpen: true, tab: ShellTab.home), ShellBack.closeSearch);
      expect(shellBack(searchOpen: true, tab: ShellTab.movies), ShellBack.closeSearch);
    });

    test('un autre onglet ramène à l’accueil', () {
      expect(shellBack(searchOpen: false, tab: ShellTab.movies), ShellBack.goHome);
      expect(shellBack(searchOpen: false, tab: ShellTab.guide), ShellBack.goHome);
    });

    test('depuis l’accueil, Bobine se ferme', () {
      expect(shellBack(searchOpen: false, tab: ShellTab.home), ShellBack.exit);
    });
  });

  group('Retour dans le lecteur', () {
    PlayerBack back({
      bool panel = false,
      bool stats = false,
      bool fullscreen = false,
      bool casting = false,
      bool tv = false,
    }) => playerBack(panelOpen: panel, statsShown: stats, fullscreen: fullscreen, casting: casting, tv: tv);

    test('un panneau, puis les statistiques, se ferment avant de quitter', () {
      expect(back(panel: true, stats: true, fullscreen: true), PlayerBack.closePanel);
      expect(back(stats: true, fullscreen: true), PlayerBack.hideStats);
    });

    test('sur l’ordinateur le plein écran se quitte d’abord, pas sur la télé (toujours plein écran)', () {
      expect(back(fullscreen: true), PlayerBack.leaveFullscreen);
      expect(back(fullscreen: true, tv: true), PlayerBack.leave);
    });

    test('pendant une diffusion, Retour réduit le lecteur et la télé continue', () {
      expect(back(casting: true), PlayerBack.minimize);
    });

    test('sinon on quitte le lecteur', () {
      expect(back(), PlayerBack.leave);
    });
  });
}
