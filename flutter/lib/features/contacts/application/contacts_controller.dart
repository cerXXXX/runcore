import '../../../core/platform/runcore_channel.dart';
import '../data/contacts_repository.dart';
import '../domain/chat_contact.dart';

class ContactsController {
  ContactsController({required ContactsRepository repository})
    : _repository = repository;

  final ContactsRepository _repository;

  Future<ContactsViewData> refresh({
    required ChatContact? selectedContact,
    required bool showMyProfileInRightPane,
  }) async {
    final snapshot = await _repository.loadSnapshot();
    ChatContact? nextSelected = selectedContact;
    if (nextSelected != null) {
      final match = snapshot.contacts.where(
        (c) => c.destHashHex == nextSelected!.destHashHex,
      );
      nextSelected = match.isEmpty ? null : match.first;
      if (nextSelected?.destHashHex.isEmpty ?? true) {
        nextSelected = null;
      }
    }

    return ContactsViewData(
      paths: snapshot.paths,
      contacts: snapshot.contacts,
      me: snapshot.me,
      selectedContact: nextSelected,
      showMyProfileInRightPane: snapshot.me == null
          ? false
          : showMyProfileInRightPane,
    );
  }
}

class ContactsViewData {
  const ContactsViewData({
    required this.paths,
    required this.contacts,
    required this.me,
    required this.selectedContact,
    required this.showMyProfileInRightPane,
  });

  final RuncorePaths paths;
  final List<ChatContact> contacts;
  final ChatContact? me;
  final ChatContact? selectedContact;
  final bool showMyProfileInRightPane;
}
