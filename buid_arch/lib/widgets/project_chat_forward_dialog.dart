import 'package:flutter/material.dart';

import '../models/project_chat_conversation.dart';

Future<List<ProjectChatConversation>?> showProjectChatForwardDialog({
  required BuildContext context,
  required List<ProjectChatConversation> conversations,
}) {
  final selectedIds = <String>{};

  return showDialog<List<ProjectChatConversation>>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Forward to'),
        content: SizedBox(
          width: double.maxFinite,
          height: 360,
          child: ListView.builder(
            itemCount: conversations.length,
            itemBuilder: (context, index) {
              final conversation = conversations[index];
              return CheckboxListTile(
                value: selectedIds.contains(conversation.id),
                onChanged: (selected) {
                  setState(() {
                    if (selected == true) {
                      selectedIds.add(conversation.id);
                    } else {
                      selectedIds.remove(conversation.id);
                    }
                  });
                },
                secondary: Icon(
                  conversation.isGroup
                      ? Icons.groups_2_outlined
                      : Icons.person_outline,
                ),
                title: Text(
                  conversation.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  conversation.isGroup
                      ? '${conversation.projectName} · Project group'
                      : '${conversation.projectName} · Private chat',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                controlAffinity: ListTileControlAffinity.trailing,
                contentPadding: EdgeInsets.zero,
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: selectedIds.isEmpty
                ? null
                : () => Navigator.pop(
                      context,
                      conversations
                          .where((chat) => selectedIds.contains(chat.id))
                          .toList(growable: false),
                    ),
            child: Text(
              selectedIds.isEmpty
                  ? 'Forward'
                  : 'Forward (${selectedIds.length})',
            ),
          ),
        ],
      ),
    ),
  );
}
