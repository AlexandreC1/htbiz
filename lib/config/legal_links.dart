/// Public web pages the app links to.
///
/// OWNER ACTION: these point at GitHub Pages for this repository. Replace
/// [_host] with wherever the `landing/` folder is actually published, and
/// enter the same delete-account URL in the Play Console Data safety form.
class LegalLinks {
  static const _host = 'https://alexandrec1.github.io/htbiz';

  static final terms = Uri.parse('$_host/terms.html');
  static final guidelines = Uri.parse('$_host/guidelines.html');
  static final privacy = Uri.parse('$_host/privacy.html');

  /// Where an account can be deleted without the app.
  static final deleteAccount = Uri.parse('$_host/delete-account.html');
}
