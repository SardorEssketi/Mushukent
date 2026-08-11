import 'dart:async';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../features/add_observation/application/add_observation_controller.dart';
import '../../features/profile/presentation/screens/profile_screen.dart';
import '../localization/app_strings.dart';
import '../location/location_service.dart';
import '../media/image_upload_preprocessor.dart';
import '../onboarding/authenticated_onboarding_flow.dart';
import '../validation/phone_numbers.dart';

class AppShellScaffold extends ConsumerWidget {
  const AppShellScaffold({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  void _selectBranch(BuildContext context, WidgetRef ref, int index) {
    if (index == 2) {
      _showAddOptions(context, ref);
      return;
    }

    navigationShell.goBranch(
      index,
      initialLocation: true,
    );
  }

  Future<void> _showAddOptions(BuildContext context, WidgetRef ref) {
    final controller = ref.read(addObservationControllerProvider.notifier);
    final strings = ref.read(appStringsProvider);

    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  strings.add,
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                _AddOptionTile(
                  icon: Icons.photo_library_outlined,
                  title: strings.chooseFromGallery,
                  subtitle: strings.gallerySubtitle,
                  onTap: () async {
                    final result = await FilePicker.pickFiles(
                      type: FileType.image,
                      withData: true,
                    );
                    final file = result?.files.singleOrNull;
                    final bytes = file?.bytes;
                    if (file == null || bytes == null) {
                      return;
                    }
                    final prepared = await prepareImageForUpload(
                      bytes: bytes,
                      filename: file.name,
                    );

                    controller.reset();
                    controller.setPhoto(
                      bytes: prepared.bytes,
                      filename: prepared.filename,
                      contentType: prepared.contentType,
                    );
                    if (sheetContext.mounted) {
                      Navigator.of(sheetContext).pop();
                      context.go('/add/details');
                    }
                  },
                ),
                const SizedBox(height: 8),
                _AddOptionTile(
                  icon: Icons.photo_camera_outlined,
                  title: strings.takePhoto,
                  subtitle: strings.cameraSubtitle,
                  onTap: () async {
                    final image = await ImagePicker().pickImage(
                      source: ImageSource.camera,
                      imageQuality: 90,
                    );
                    if (image == null) {
                      return;
                    }

                    final prepared = await prepareImageForUpload(
                      bytes: await image.readAsBytes(),
                      filename: image.name,
                    );
                    controller.reset();
                    controller.setPhoto(
                      bytes: prepared.bytes,
                      filename: prepared.filename,
                      contentType: prepared.contentType,
                    );
                    final location =
                        await LocationService().resolveCurrentLocation();
                    controller.setLocation(location);
                    unawaited(controller.loadNearbyCats());
                    if (sheetContext.mounted) {
                      Navigator.of(sheetContext).pop();
                      context.go('/add/details');
                    }
                  },
                ),
                const SizedBox(height: 8),
                _AddOptionTile(
                  icon: Icons.search_outlined,
                  title: strings.lostPet,
                  subtitle: strings.lostPetSubtitle,
                  onTap: () async {
                    final profile = await ref.read(profileMeProvider.future);
                    final phone = profile.phoneNumber?.trim() ?? '';
                    if (!sheetContext.mounted) {
                      return;
                    }
                    Navigator.of(sheetContext).pop();
                    if (phone.isEmpty || !isValidUzbekPhoneNumber(phone)) {
                      if (!context.mounted) {
                        return;
                      }
                      final editProfile = await showDialog<bool>(
                        context: context,
                        builder: (dialogContext) => AlertDialog(
                          title: Text(strings.phoneNumberRequired),
                          content: Text(strings.phoneNumberRequiredForLostPet),
                          actions: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(false),
                              child: Text(strings.cancel),
                            ),
                            FilledButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(true),
                              child: Text(strings.editProfile),
                            ),
                          ],
                        ),
                      );
                      if (editProfile == true && context.mounted) {
                        context.go('/profile/edit');
                      }
                      return;
                    }
                    if (context.mounted) {
                      context.go('/add/lost-pet');
                    }
                  },
                ),
                const SizedBox(height: 8),
                _AddOptionTile(
                  icon: Icons.home_outlined,
                  title: 'Give pet for adoption',
                  subtitle: 'Pet photo, description, and owner contacts.',
                  onTap: () async {
                    final profile = await ref.read(profileMeProvider.future);
                    final phone = profile.phoneNumber?.trim() ?? '';
                    if (!sheetContext.mounted) {
                      return;
                    }
                    Navigator.of(sheetContext).pop();
                    if (phone.isEmpty || !isValidUzbekPhoneNumber(phone)) {
                      if (!context.mounted) {
                        return;
                      }
                      final editProfile = await showDialog<bool>(
                        context: context,
                        builder: (dialogContext) => AlertDialog(
                          title: Text(strings.phoneNumberRequired),
                          content: const Text(
                            'Add a phone number before creating an adoption post so people can reach you.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(false),
                              child: Text(strings.cancel),
                            ),
                            FilledButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(true),
                              child: Text(strings.editProfile),
                            ),
                          ],
                        ),
                      );
                      if (editProfile == true && context.mounted) {
                        context.go('/profile/edit');
                      }
                      return;
                    }
                    if (context.mounted) {
                      context.go('/add/adoption');
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);

    return Scaffold(
      body: AuthenticatedOnboardingFlow(child: navigationShell),
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) => _selectBranch(context, ref, index),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.dynamic_feed_outlined),
            selectedIcon: const Icon(Icons.dynamic_feed),
            label: strings.feed,
          ),
          NavigationDestination(
            icon: const Icon(Icons.map_outlined),
            selectedIcon: const Icon(Icons.map),
            label: strings.map,
          ),
          NavigationDestination(
            icon: const Icon(Icons.add_circle_outline),
            selectedIcon: const Icon(Icons.add_circle),
            label: strings.add,
          ),
          NavigationDestination(
            icon: const Icon(Icons.emoji_events_outlined),
            selectedIcon: const Icon(Icons.emoji_events),
            label: strings.leaders,
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline),
            selectedIcon: const Icon(Icons.person),
            label: strings.profile,
          ),
        ],
      ),
    );
  }
}

class _AddOptionTile extends StatelessWidget {
  const _AddOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
