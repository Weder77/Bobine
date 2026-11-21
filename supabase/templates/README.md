# E-mails du compte Bobine

Une copie des modèles d'e-mails du projet Supabase, pour en garder la trace. Ce sont ceux du tableau de bord
(*Authentication → Emails*) au 21 novembre 2026 : une modification là-bas doit être reportée ici, et inversement.

| Modèle Supabase | Fichier | Objet |
|---|---|---|
| Confirm sign up | `confirmation.html` | `{{ .Token }} est ton code Bobine` |
| Reset password | `recovery.html` | `{{ .Token }} est ton code Bobine` |
| Password changed (notification) | `password_changed_notification.html` | `Le mot de passe de ton compte Bobine a changé` |
| Email address changed (notification) | `email_changed_notification.html` | `L'adresse de ton compte Bobine a changé` |

Les autres modèles (Invite user, Magic link, Change email address, Reauthentication) ne servent ni à l'appli ni au
site : ils sont restés ceux de Supabase.

## Ce qu'il faut savoir

- **Des codes, pas des liens** : l'appli et le site demandent de saisir le code (`{{ .Token }}`, 6 chiffres). Le code
  est aussi dans l'objet, lisible depuis la notification du téléphone quand on se connecte sur la télé.
- **« Reset password » sert à deux choses** : choisir un nouveau mot de passe (dans l'appli ou sur le site) et
  supprimer son compte sans mot de passe (getbobine.app/compte/suppression/). Le texte parle des deux.
- **Variables** : `{{ .Token }}` et `{{ .Email }}` partout ; `{{ .OldEmail }}` seulement dans « Email address changed ».
- **Rien d'extérieur** : ni image, ni police, ni lien de suivi. Fond clair, beaucoup de messageries inversant les
  fonds sombres.
- **Envoi** : SMTP de Resend, depuis `no-reply@getbobine.app` (domaine vérifié : DKIM `resend._domainkey`, sous-domaine
  `send`, DMARC).
