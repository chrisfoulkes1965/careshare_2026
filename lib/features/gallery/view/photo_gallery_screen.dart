import "package:flutter/material.dart";
import "package:flutter_bloc/flutter_bloc.dart";
import "package:image_picker/image_picker.dart";

import "../../members/models/care_group_member.dart";
import "../../members/repository/members_repository.dart";
import "../../profile/cubit/profile_cubit.dart";
import "../../profile/cubit/profile_state.dart";
import "../models/gallery_photo.dart";
import "../repository/photo_gallery_repository.dart";

bool _isReceivesCareOnlyMember(CareGroupMember? me) {
  if (me == null) {
    return true;
  }
  if (!me.roles.contains("receives_care")) {
    return false;
  }
  const elevated = {
    "principal_carer",
    "carer",
    "financial_manager",
    "power_of_attorney",
    "care_group_administrator",
  };
  for (final r in me.roles) {
    if (elevated.contains(r)) {
      return false;
    }
  }
  return true;
}

bool _canViewGallery(CareGroupMember? me) {
  return me != null && !_isReceivesCareOnlyMember(me);
}

bool _canAddPhotos(CareGroupMember? me) {
  if (me == null) {
    return false;
  }
  return me.roles.contains("principal_carer") ||
      me.roles.contains("carer") ||
      me.roles.contains("power_of_attorney") ||
      me.roles.contains("care_group_administrator");
}

bool _canDeletePhoto({
  required CareGroupMember? me,
  required String uploadedBy,
}) {
  if (me == null) {
    return false;
  }
  if (me.userId == uploadedBy) {
    return true;
  }
  return me.roles.contains("principal_carer") ||
      me.roles.contains("power_of_attorney") ||
      me.roles.contains("care_group_administrator");
}

class PhotoGalleryScreen extends StatefulWidget {
  const PhotoGalleryScreen({super.key});

  @override
  State<PhotoGalleryScreen> createState() => _PhotoGalleryScreenState();
}

class _PhotoGalleryScreenState extends State<PhotoGalleryScreen> {
  bool _uploadBusy = false;

  Future<void> _showAddSheet(String careGroupId) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_camera_outlined),
                  title: const Text("Take photo"),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _pickAndUpload(careGroupId, ImageSource.camera);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text("Choose from gallery"),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _pickAndUpload(careGroupId, ImageSource.gallery);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickAndUpload(String careGroupId, ImageSource source) async {
    final picker = ImagePicker();
    final x = await picker.pickImage(
      source: source,
      maxWidth: 2400,
      maxHeight: 2400,
      imageQuality: 88,
    );
    if (x == null || !mounted) {
      return;
    }
    final bytes = await x.readAsBytes();
    if (!mounted) {
      return;
    }
    setState(() => _uploadBusy = true);
    try {
      await context.read<PhotoGalleryRepository>().uploadPhoto(
            careGroupId: careGroupId,
            bytes: bytes,
            fileName: x.name,
            mimeType: x.mimeType,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Photo added to the gallery.")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Could not upload: $e")),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _uploadBusy = false);
      }
    }
  }

  Future<void> _confirmDelete(String careGroupId, GalleryPhoto photo) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Remove photo?"),
        content: const Text(
          "This removes the photo for everyone in your care group.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text("Cancel"),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text("Remove"),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) {
      return;
    }
    try {
      await context.read<PhotoGalleryRepository>().deletePhoto(
            careGroupId: careGroupId,
            photo: photo,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Photo removed.")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Could not remove: $e")),
        );
      }
    }
  }

  void _openPhoto(BuildContext context, GalleryPhoto photo) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return Dialog.fullscreen(
          backgroundColor: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              InteractiveViewer(
                minScale: 0.5,
                maxScale: 4,
                child: Center(
                  child: Image.network(
                    photo.downloadUrl,
                    fit: BoxFit.contain,
                    loadingBuilder: (c, w, p) {
                      if (p == null) {
                        return w;
                      }
                      return const Padding(
                        padding: EdgeInsets.all(48),
                        child: CircularProgressIndicator(color: Colors.white70),
                      );
                    },
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white54,
                      size: 64,
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: Align(
                  alignment: Alignment.topRight,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ),
              ),
              if (photo.caption != null && photo.caption!.isNotEmpty)
                SafeArea(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      width: double.infinity,
                      margin: const EdgeInsets.all(16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        photo.caption!,
                        style: const TextStyle(color: Colors.white),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProfileCubit, ProfileState>(
      builder: (context, state) {
        if (state is! ProfileReady) {
          return const Scaffold(
            body: Center(child: Text("Loading your profile…")),
          );
        }
        final dataId = state.activeCareGroupDataId;
        if (dataId == null || dataId.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: const Text("Photo gallery")),
            body: const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  "You need a care group before you can use the photo gallery. Complete setup first.",
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }
        final membersCg = state.activeCareGroupMemberDocId ?? dataId;
        final myUid = state.profile.uid;
        return StreamBuilder<List<CareGroupMember>>(
          stream: context.read<MembersRepository>().watchMembers(membersCg),
          builder: (context, memSnap) {
            CareGroupMember? me;
            final list = memSnap.data;
            if (list != null) {
              for (final m in list) {
                if (m.userId == myUid) {
                  me = m;
                  break;
                }
              }
            }
            final canView = _canViewGallery(me);
            final canAdd = canView && _canAddPhotos(me);
            if (!canView) {
              return Scaffold(
                appBar: AppBar(title: const Text("Photo gallery")),
                body: const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      "Your role doesn’t include access to the shared photo gallery. Ask a carer or administrator if you need access.",
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              );
            }
            final repo = context.read<PhotoGalleryRepository>();
            return Stack(
              children: [
                Scaffold(
                  appBar: AppBar(title: const Text("Photo gallery")),
                  floatingActionButton: canAdd
                      ? FloatingActionButton(
                          onPressed: _uploadBusy
                              ? null
                              : () => _showAddSheet(dataId),
                          child: const Icon(Icons.add_a_photo_outlined),
                        )
                      : null,
                  body: !repo.isAvailable
                      ? const Center(child: Text("Gallery isn’t available offline."))
                      : StreamBuilder<List<GalleryPhoto>>(
                          stream: repo.watchPhotos(dataId),
                          builder: (context, snap) {
                            if (snap.hasError) {
                              return Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Text(
                                    "Could not load photos: ${snap.error}",
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              );
                            }
                            if (!snap.hasData) {
                              return const Center(child: CircularProgressIndicator());
                            }
                            final photos = snap.data!;
                            if (photos.isEmpty) {
                              return Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.photo_library_outlined,
                                        size: 56,
                                        color: Theme.of(context).disabledColor,
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        canAdd
                                            ? "No photos yet. Tap the camera button to take one or add from your gallery."
                                            : "No photos have been shared yet.",
                                        textAlign: TextAlign.center,
                                        style: Theme.of(context).textTheme.bodyLarge,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }
                            return GridView.builder(
                              padding: const EdgeInsets.all(8),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                crossAxisSpacing: 6,
                                mainAxisSpacing: 6,
                              ),
                              itemCount: photos.length,
                              itemBuilder: (context, i) {
                                final p = photos[i];
                                final showDelete = _canDeletePhoto(
                                  me: me,
                                  uploadedBy: p.uploadedBy,
                                );
                                return Material(
                                  color: Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(8),
                                  clipBehavior: Clip.antiAlias,
                                  child: InkWell(
                                    onTap: () => _openPhoto(context, p),
                                    onLongPress: showDelete
                                        ? () => _confirmDelete(dataId, p)
                                        : null,
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        Image.network(
                                          p.downloadUrl,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) =>
                                              const Icon(Icons.broken_image_outlined),
                                        ),
                                        if (showDelete)
                                          Positioned(
                                            top: 2,
                                            right: 2,
                                            child: Material(
                                              color: Colors.black45,
                                              shape: const CircleBorder(),
                                              child: IconButton(
                                                visualDensity:
                                                    VisualDensity.compact,
                                                padding: EdgeInsets.zero,
                                                constraints: const BoxConstraints(
                                                  minWidth: 32,
                                                  minHeight: 32,
                                                ),
                                                icon: const Icon(
                                                  Icons.close,
                                                  size: 18,
                                                  color: Colors.white,
                                                ),
                                                onPressed: () =>
                                                    _confirmDelete(dataId, p),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                ),
                if (_uploadBusy)
                  const ColoredBox(
                    color: Color(0x66000000),
                    child: Center(child: CircularProgressIndicator()),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}
