// profile_screen.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/login_screen.dart';
import '../screens/history_screen.dart';
import '../screens/scan_document_screen.dart'; // Diperlukan untuk DocumentModel

class ProfileScreen extends StatelessWidget {
  final String userEmail;
  final Function(DocumentModel) onRestore;

  const ProfileScreen({
    super.key,
    required this.userEmail,
    required this.onRestore,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profil'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.person),
              title: const Text('Akun'),
              subtitle: Text(userEmail),
            ),
            const Divider(),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              child: ListTile(
                leading: const Icon(Icons.delete_forever, color: Colors.red),
                title: const Text('Dokumen Dihapus'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => HistoryScreen(
                        userEmail: userEmail,
                        historyType: HistoryType.deleted,
                        onRestore: onRestore,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              child: ListTile(
                leading: const Icon(Icons.download, color: Colors.blue),
                title: const Text('Dokumen Diunduh'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => HistoryScreen(
                        userEmail: userEmail,
                        historyType: HistoryType.downloaded,
                        onRestore: (doc) {
                          // Tidak ada aksi restore untuk dokumen yang diunduh,
                          // jadi kita berikan fungsi kosong.
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8), // Memberi sedikit jarak
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              child: ListTile(
                leading: const Icon(Icons.logout, color: Colors.redAccent),
                title: const Text('Keluar'),
                onTap: () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('isLoggedIn', false);
                  await prefs.remove('currentUserEmail');
                  if (context.mounted) {
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (context) => const LoginScreen()),
                      (Route<dynamic> route) => false,
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}