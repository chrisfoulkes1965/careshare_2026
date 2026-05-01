import "package:file_picker/file_picker.dart";
import "package:flutter/material.dart";
import "package:flutter_bloc/flutter_bloc.dart";
import "package:go_router/go_router.dart";
import "package:url_launcher/url_launcher.dart";

import "../../members/models/care_group_member.dart";
import "../../members/repository/members_repository.dart";
import "../../profile/cubit/profile_cubit.dart";
import "../../profile/cubit/profile_state.dart";
import "../models/library_file.dart";
import "../models/library_folder.dart";
import "../repository/documents_library_repository.dart";

/// Aligned with Firestore: [isReceivesCareOnlyMember] cannot read the library.
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

bool _canViewDocumentLibrary(CareGroupMember? me) {
  return me != null && !_isReceivesCareOnlyMember(me);
}

bool _canManageLibrary(CareGroupMember? me) {
  if (me == null) {
    return false;
  }
  return me.roles.contains("principal_carer") ||
      me.roles.contains("carer") ||
      me.roles.contains("power_of_attorney") ||
      me.roles.contains("care_group_administrator");
}

String _formatBytes(int n) {
  if (n < 1024) {
    return "$n B";
  }
  if (n < 1024 * 1024) {
    return "${(n / 1024).toStringAsFixed(1)} KB";
  }
  return "${(n / (1024 * 1024)).toStringAsFixed(1)} MB";
}

Future<void> _openDownloadUrl(
  BuildContext context,
  String url,
) async {
  final u = Uri.tryParse(url);
  if (u == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Invalid link.")),
      );
    }
    return;
  }
  if (!await canLaunchUrl(u)) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not open the file.")),
      );
    }
    return;
  }
  await launchUrl(
    u,
    mode: LaunchMode.externalApplication,
  );
}

class DocumentLibraryScreen extends StatefulWidget {
  const DocumentLibraryScreen({super.key});

  @override
  State<DocumentLibraryScreen> createState() => _DocumentLibraryScreenState();
}

class _DocumentLibraryScreenState extends State<DocumentLibraryScreen> {
  final List<({String id, String name})> _path = [];
  bool _trashMode = false;

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
            appBar: AppBar(title: const Text("Document library")),
            body: const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  "You need a care group to use the document library. Complete setup first.",
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
            if (memSnap.data == null) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            CareGroupMember? me;
            for (final m in memSnap.data!) {
              if (m.userId == myUid) {
                me = m;
                break;
              }
            }
            if (!_canViewDocumentLibrary(me)) {
              return Scaffold(
                appBar: AppBar(
                  title: const Text("Document library"),
                ),
                body: const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      "This area is for carers and family members. Ask a principal carer if you need access to shared files.",
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              );
            }
            final canManage = _canManageLibrary(me);
            return _DocumentLibraryScaffold(
              dataCareGroupId: dataId,
              canManage: canManage,
              path: _path,
              trashMode: _trashMode,
              onPopFolder: _path.isEmpty
                  ? null
                  : () {
                      setState(() {
                        _path.removeLast();
                      });
                    },
              onEnterTrash: () {
                setState(() {
                  _trashMode = true;
                });
              },
              onExitTrash: () {
                setState(() {
                  _trashMode = false;
                });
              },
              onOpenFolder: (f) {
                setState(() {
                  _path.add((id: f.id, name: f.name));
                });
              },
            );
          },
        );
      },
    );
  }
}

class _DocumentLibraryScaffold extends StatelessWidget {
  const _DocumentLibraryScaffold({
    required this.dataCareGroupId,
    required this.canManage,
    required this.path,
    required this.trashMode,
    this.onPopFolder,
    required this.onEnterTrash,
    required this.onExitTrash,
    required this.onOpenFolder,
  });

  final String dataCareGroupId;
  final bool canManage;
  final List<({String id, String name})> path;
  final bool trashMode;
  final VoidCallback? onPopFolder;
  final VoidCallback onEnterTrash;
  final VoidCallback onExitTrash;
  final void Function(LibraryFolder f) onOpenFolder;

  @override
  Widget build(BuildContext context) {
    final parentId = path.isEmpty ? "" : path.last.id;
    final title = trashMode
        ? "Trash"
        : (path.isEmpty
            ? "Document library"
            : path.map((e) => e.name).join(" / "));
    return Scaffold(
      appBar: AppBar(
        title: Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        leading: IconButton(
          icon: Icon(
            trashMode ? Icons.close : Icons.arrow_back,
          ),
          onPressed: () {
            if (trashMode) {
              onExitTrash();
            } else if (onPopFolder != null) {
              onPopFolder!();
            } else {
              if (context.canPop()) {
                context.pop();
              } else {
                Navigator.of(context).maybePop();
              }
            }
          },
        ),
        leadingWidth: 48,
        actions: [
          if (canManage && !trashMode) ...[
            IconButton(
              icon: const Icon(Icons.create_new_folder_outlined),
              tooltip: "New folder",
              onPressed: () => _onCreateFolder(
                context,
                dataCareGroupId: dataCareGroupId,
                parentFolderId: parentId,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.upload_file_outlined),
              tooltip: "Upload",
              onPressed: () => _onUpload(
                context,
                dataCareGroupId: dataCareGroupId,
                parentFolderId: parentId,
              ),
            ),
          ],
          if (!trashMode)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: "Trash",
              onPressed: onEnterTrash,
            )
          else
            const SizedBox(width: 8),
        ],
      ),
      body: !trashMode
          ? _ActiveLibraryBody(
              dataCareGroupId: dataCareGroupId,
              canManage: canManage,
              parentFolderId: parentId,
              onOpenFolder: onOpenFolder,
            )
          : _TrashBody(
              dataCareGroupId: dataCareGroupId,
              canManage: canManage,
            ),
    );
  }

  Future<void> _onCreateFolder(
    BuildContext context, {
    required String dataCareGroupId,
    required String parentFolderId,
  }) async {
    final repo = context.read<DocumentsLibraryRepository>();
    if (!repo.isAvailable) {
      return;
    }
    final c = TextEditingController();
    final name = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("New folder"),
        content: TextField(
          controller: c,
          decoration: const InputDecoration(
            labelText: "Folder name",
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              ctx,
              c.text.trim().isEmpty ? null : c.text.trim(),
            ),
            child: const Text("Create"),
          ),
        ],
      ),
    );
    if (name == null || !context.mounted) {
      return;
    }
    try {
      await repo.createFolder(
        dataCareGroupId,
        name: name,
        parentFolderId: parentFolderId,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  Future<void> _onUpload(
    BuildContext context, {
    required String dataCareGroupId,
    required String parentFolderId,
  }) async {
    final repo = context.read<DocumentsLibraryRepository>();
    if (!repo.isAvailable) {
      return;
    }
    final result = await FilePicker.platform.pickFiles(
      withData: true,
      allowMultiple: true,
    );
    if (result == null || !context.mounted) {
      return;
    }
    for (final f in result.files) {
      if (!context.mounted) {
        return;
      }
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Expanded(
                child: Text("Uploading…"),
              ),
            ],
          ),
        ),
      );
      try {
        await repo.uploadFile(
          dataCareGroupId,
          folderId: parentFolderId,
          file: f,
        );
      } catch (e) {
        if (context.mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                "${f.name}: $e",
                maxLines: 4,
              ),
            ),
          );
        }
        continue;
      }
      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Uploaded ${f.name}"),
          ),
        );
      }
    }
  }
}

class _ActiveLibraryBody extends StatelessWidget {
  const _ActiveLibraryBody({
    required this.dataCareGroupId,
    required this.canManage,
    required this.parentFolderId,
    required this.onOpenFolder,
  });

  final String dataCareGroupId;
  final bool canManage;
  final String parentFolderId;
  final void Function(LibraryFolder f) onOpenFolder;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<DocumentsLibraryRepository>();
    if (!repo.isAvailable) {
      return const Center(child: Text("Cloud storage is not available."));
    }
    return StreamBuilder<List<LibraryFolder>>(
      stream: repo.watchFoldersInParent(
        dataCareGroupId,
        parentFolderId: parentFolderId,
        inTrash: false,
      ),
      builder: (context, folderSnap) {
        return StreamBuilder<List<LibraryFile>>(
          stream: repo.watchFilesInFolder(
            dataCareGroupId,
            folderId: parentFolderId,
            inTrash: false,
          ),
          builder: (context, fileSnap) {
            if (!folderSnap.hasData || !fileSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final folders = folderSnap.data ?? [];
            final files = fileSnap.data ?? [];
            if (folders.isEmpty && files.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 64),
                  Center(
                    child: Text(
                      "No documents here yet. Upload a file or add a folder from the app bar (carers and principals).",
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              );
            }
            return ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                ...folders.map(
                  (f) => _FolderTile(
                    folder: f,
                    onTap: () => onOpenFolder(f),
                    onMore: canManage
                        ? (ctx) => _FolderActions.show(
                            ctx,
                            dataCareGroupId: dataCareGroupId,
                            folder: f,
                          )
                        : null,
                  ),
                ),
                ...files.map(
                  (e) => _FileTile(
                    file: e,
                    onOpen: () => _openDownloadUrl(
                      context,
                      e.downloadUrl,
                    ),
                    onMore: canManage
                        ? (ctx) => _FileActions.show(
                            ctx,
                            dataCareGroupId: dataCareGroupId,
                            file: e,
                            parentFolderId: parentFolderId,
                            includeTrash: true,
                            includeMove: true,
                          )
                        : null,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _FolderTile extends StatelessWidget {
  const _FolderTile({
    required this.folder,
    this.onTap,
    this.onMore,
  });

  final LibraryFolder folder;
  final VoidCallback? onTap;
  final void Function(BuildContext)? onMore;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.folder_outlined),
      title: Text(folder.name),
      onTap: onTap,
      trailing: onMore != null
          ? IconButton(
              icon: const Icon(Icons.more_vert),
              onPressed: () => onMore!(context),
            )
          : null,
    );
  }
}

class _FileTile extends StatelessWidget {
  const _FileTile({
    required this.file,
    required this.onOpen,
    this.onMore,
  });

  final LibraryFile file;
  final VoidCallback onOpen;
  final void Function(BuildContext)? onMore;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.insert_drive_file_outlined),
      title: Text(
        file.displayName,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(_formatBytes(file.sizeBytes)),
      onTap: onOpen,
      trailing: onMore != null
          ? IconButton(
              icon: const Icon(Icons.more_vert),
              onPressed: () => onMore!(context),
            )
          : null,
    );
  }
}

class _FileActions {
  static Future<void> show(
    BuildContext context, {
    required String dataCareGroupId,
    required LibraryFile file,
    required String parentFolderId,
    bool includeMove = true,
    bool includeTrash = true,
  }) async {
    final repo = context.read<DocumentsLibraryRepository>();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (includeMove) ...[
                ListTile(
                  leading: const Icon(Icons.drive_file_move_outline),
                  title: const Text("Move to folder"),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showMoveFilePicker(
                      context,
                      dataCareGroupId: dataCareGroupId,
                      file: file,
                    );
                  },
                ),
              ],
              if (includeTrash)
                ListTile(
                  leading: const Icon(
                    Icons.delete_outline,
                    color: Colors.orange,
                  ),
                  title: const Text("Move to Trash"),
                  onTap: () async {
                    Navigator.pop(ctx);
                    try {
                      await repo.trashFile(
                        dataCareGroupId,
                        fileId: file.id,
                      );
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(e.toString())),
                        );
                      }
                    }
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  static void _showMoveFilePicker(
    BuildContext context, {
    required String dataCareGroupId,
    required LibraryFile file,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return _MoveFileSheet(
          dataCareGroupId: dataCareGroupId,
          file: file,
        );
      },
    );
  }
}

class _MoveFileSheet extends StatelessWidget {
  const _MoveFileSheet({
    required this.dataCareGroupId,
    required this.file,
  });

  final String dataCareGroupId;
  final LibraryFile file;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<DocumentsLibraryRepository>();
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, sc) {
        return StreamBuilder<List<LibraryFolder>>(
          stream: repo.watchAllActiveFolders(dataCareGroupId),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final list = List<LibraryFolder>.from(
              snap.data ?? const [],
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Text(
                    "Move to",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.home_outlined),
                  title: const Text("Library (top level)"),
                  onTap: () async {
                    final nav = Navigator.of(context);
                    try {
                      await repo.moveFileTo(
                        dataCareGroupId,
                        fileId: file.id,
                        newFolderId: "",
                      );
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(e.toString())),
                        );
                      }
                      return;
                    }
                    nav.pop();
                  },
                ),
                Expanded(
                  child: list.isEmpty
                      ? const Center(
                          child: Text("No other folders yet. Create a folder on the home screen of the library."),
                        )
                      : ListView(
                          controller: sc,
                          children: [
                            for (final f in _sortedFoldersByPath(
                              flat: list,
                            ))
                              ListTile(
                                leading: const Icon(Icons.folder_outlined),
                                title: Text(
                                  f.label,
                                  maxLines: 2,
                                ),
                                onTap: () async {
                                  if (f.id == file.folderId) {
                                    Navigator.of(context).pop();
                                    return;
                                  }
                                  try {
                                    await repo.moveFileTo(
                                      dataCareGroupId,
                                      fileId: file.id,
                                      newFolderId: f.id,
                                    );
                                  } catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(e.toString()),
                                        ),
                                      );
                                    }
                                    return;
                                  }
                                  if (context.mounted) {
                                    Navigator.of(context).pop();
                                  }
                                },
                              ),
                          ],
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

List<({String id, String label})> _sortedFoldersByPath({
  required List<LibraryFolder> flat,
}) {
  byId(String id) {
    for (final f in flat) {
      if (f.id == id) {
        return f;
      }
    }
    return null;
  }

  String labelFor(LibraryFolder f) {
    final segs = <String>[];
    var cur = f;
    for (var i = 0; i < 40; i++) {
      segs.add(cur.name);
      final p = cur.parentFolderId;
      if (p.isEmpty) {
        break;
      }
      final n = byId(p);
      if (n == null) {
        break;
      }
      cur = n;
    }
    return segs.reversed.join(" / ");
  }

  final res = <({String id, String label})>[];
  for (final f in flat) {
    if (f.inTrash) {
      continue;
    }
    res.add((
      id: f.id,
      label: labelFor(f),
    ),);
  }
  res.sort((a, b) => a.label.toLowerCase().compareTo(
        b.label.toLowerCase(),
      ));
  return res;
}

class _FolderActions {
  static Future<void> show(
    BuildContext context, {
    required String dataCareGroupId,
    required LibraryFolder folder,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text("Rename"),
                onTap: () {
                  Navigator.pop(ctx);
                  _promptRename(
                    context,
                    dataCareGroupId: dataCareGroupId,
                    folder: folder,
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.drive_file_move_outline),
                title: const Text("Move to folder"),
                onTap: () {
                  Navigator.pop(ctx);
                  _showMoveFolderPicker(
                    context,
                    dataCareGroupId: dataCareGroupId,
                    folder: folder,
                  );
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.delete_sweep_outlined,
                  color: Colors.orange,
                ),
                title: const Text("Move folder to Trash"),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmTrashFolder(
                    context,
                    dataCareGroupId: dataCareGroupId,
                    folder: folder,
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  static Future<void> _promptRename(
    BuildContext context, {
    required String dataCareGroupId,
    required LibraryFolder folder,
  }) async {
    final repo = context.read<DocumentsLibraryRepository>();
    final c = TextEditingController(text: folder.name);
    final name = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Rename folder"),
        content: TextField(
          controller: c,
          decoration: const InputDecoration(
            labelText: "Name",
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          FilledButton(
            onPressed: () {
              final t = c.text.trim();
              if (t.isNotEmpty) {
                Navigator.pop(ctx, t);
              } else {
                Navigator.pop(ctx);
              }
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
    if (name == null) {
      return;
    }
    try {
      await repo.renameFolder(
        dataCareGroupId,
        folderId: folder.id,
        newName: name,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  static void _showMoveFolderPicker(
    BuildContext context, {
    required String dataCareGroupId,
    required LibraryFolder folder,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return _MoveFolderSheet(
          dataCareGroupId: dataCareGroupId,
          movingFolder: folder,
        );
      },
    );
  }

  static Future<void> _confirmTrashFolder(
    BuildContext context, {
    required String dataCareGroupId,
    required LibraryFolder folder,
  }) async {
    final go = await showDialog<bool?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Move to Trash?"),
        content: Text(
          "“${folder.name}” and everything inside it will be moved to Trash. "
          "Files are not permanently removed.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Move to Trash"),
          ),
        ],
      ),
    );
    if (go != true || !context.mounted) {
      return;
    }
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Expanded(
              child: Text("Moving to Trash…"),
            ),
          ],
        ),
      ),
    );
    try {
      await context.read<DocumentsLibraryRepository>().trashFolderRecursively(
        dataCareGroupId,
        folderId: folder.id,
      );
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
      return;
    }
    if (context.mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Folder moved to Trash. You can restore it from the Trash view."),
        ),
      );
    }
  }
}

class _MoveFolderSheet extends StatelessWidget {
  const _MoveFolderSheet({
    required this.dataCareGroupId,
    required this.movingFolder,
  });

  final String dataCareGroupId;
  final LibraryFolder movingFolder;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<DocumentsLibraryRepository>();
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, sc) {
        return StreamBuilder<List<LibraryFolder>>(
          stream: repo.watchAllActiveFolders(dataCareGroupId),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            return FutureBuilder<Set<String>>(
              future: repo.folderSubtreeIds(
                dataCareGroupId,
                rootId: movingFolder.id,
              ),
              builder: (context, exSnap) {
                if (!exSnap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final ex = exSnap.data ?? {};
                final all = List<LibraryFolder>.from(
                  snap.data ?? const [],
                );
                final targets = all
                    .where(
                      (f) => !ex.contains(f.id),
                    )
                    .toList();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: Text(
                        "Move folder to",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.home_outlined),
                      title: const Text("Library (top level)"),
                      onTap: () async {
                        if (movingFolder.parentFolderId.isEmpty) {
                          if (context.mounted) {
                            Navigator.of(context).pop();
                          }
                          return;
                        }
                        final nav = Navigator.of(context);
                        try {
                          await repo.moveFolderTo(
                            dataCareGroupId,
                            folderId: movingFolder.id,
                            newParentFolderId: "",
                          );
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(e.toString())),
                            );
                          }
                          return;
                        }
                        if (context.mounted) {
                          nav.pop();
                        }
                      },
                    ),
                    Expanded(
                      child: targets.isEmpty
                          ? const Center(
                              child: Text("No other destinations. Create a folder, or this folder is already in the only possible place."),
                            )
                          : ListView(
                              controller: sc,
                              children: [
                                for (final t in _sortedFoldersByPath(
                                  flat: targets,
                                ))
                                  ListTile(
                                    leading: const Icon(
                                      Icons.folder_outlined,
                                    ),
                                    title: Text(
                                      t.label,
                                      maxLines: 2,
                                    ),
                                    onTap: () async {
                                      if (t.id ==
                                          movingFolder.parentFolderId) {
                                        if (context.mounted) {
                                          Navigator.of(
                                            context,
                                          ).pop();
                                        }
                                        return;
                                      }
                                      try {
                                        await repo.moveFolderTo(
                                          dataCareGroupId,
                                          folderId: movingFolder.id,
                                          newParentFolderId: t.id,
                                        );
                                      } catch (e) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                e.toString(),
                                              ),
                                            ),
                                          );
                                        }
                                        return;
                                      }
                                      if (context.mounted) {
                                        Navigator.of(
                                          context,
                                        ).pop();
                                      }
                                    },
                                  ),
                              ],
                            ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}

class _TrashBody extends StatelessWidget {
  const _TrashBody({
    required this.dataCareGroupId,
    required this.canManage,
  });

  final String dataCareGroupId;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<DocumentsLibraryRepository>();
    if (!repo.isAvailable) {
      return const Center(
        child: Text("Cloud storage is not available."),
      );
    }
    return StreamBuilder<List<LibraryFolder>>(
      stream: repo.watchTrashedFolders(
        dataCareGroupId,
      ),
      builder: (context, folderSnap) {
        return StreamBuilder<List<LibraryFile>>(
          stream: repo.watchTrashedFiles(
            dataCareGroupId,
          ),
          builder: (context, fileSnap) {
            if (!folderSnap.hasData || !fileSnap.hasData) {
              return const Center(
                child: CircularProgressIndicator(),
              );
            }
            final folders = folderSnap.data ?? const [];
            final files = fileSnap.data ?? const [];
            if (folders.isEmpty && files.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    "Trash is empty. Deleted items and folders are kept here. Nothing is removed from storage from this screen.",
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            return ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                if (folders.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
                    child: Text(
                      "Folders",
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  for (final f in folders) ...[
                    _FolderTile(
                      folder: f,
                      onTap: canManage
                          ? () {
                              _TrashFolderMenu.runRestore(
                                context,
                                dataCareGroupId: dataCareGroupId,
                                folder: f,
                              );
                            }
                          : null,
                    ),
                  ],
                ],
                if (files.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Text(
                      "Files",
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  for (final e in files) ...[
                    _FileTile(
                      file: e,
                      onOpen: () {
                        if (e.downloadUrl.isNotEmpty) {
                          _openDownloadUrl(
                            context,
                            e.downloadUrl,
                          );
                        }
                      },
                      onMore: canManage
                          ? (ctx) => _TrashFileMenu.show(
                                ctx,
                                dataCareGroupId: dataCareGroupId,
                                file: e,
                              )
                          : null,
                    ),
                  ],
                ],
              ],
            );
          },
        );
      },
    );
  }
}

class _TrashFileMenu {
  static Future<void> show(
    BuildContext context, {
    required String dataCareGroupId,
    required LibraryFile file,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: ListTile(
            leading: const Icon(Icons.restore),
            title: const Text("Restore to library"),
            onTap: () async {
              Navigator.pop(ctx);
              showDialog<void>(
                context: context,
                barrierDismissible: false,
                builder: (c) => const AlertDialog(
                  content: Row(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(width: 16),
                      Expanded(
                        child: Text("Restoring…"),
                      ),
                    ],
                  ),
                ),
              );
              try {
                await context
                    .read<DocumentsLibraryRepository>()
                    .restoreFile(
                  dataCareGroupId,
                  fileId: file.id,
                );
              } catch (e) {
                if (context.mounted) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(e.toString())),
                  );
                }
                return;
              }
              if (context.mounted) {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("File restored."),
                  ),
                );
              }
            },
          ),
        );
      },
    );
  }
}

class _TrashFolderMenu {
  static Future<void> runRestore(
    BuildContext context, {
    required String dataCareGroupId,
    required LibraryFolder folder,
  }) async {
    if (!context.read<DocumentsLibraryRepository>().isAvailable) {
      return;
    }
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (c) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Expanded(
              child: Text("Restoring…"),
            ),
          ],
        ),
      ),
    );
    try {
      await context
          .read<DocumentsLibraryRepository>()
          .restoreFolderRecursively(
        dataCareGroupId,
        folderId: folder.id,
      );
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
      return;
    }
    if (context.mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Folder and contents restored."),
        ),
      );
    }
  }
}
