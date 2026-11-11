import 'package:buid_arch/models/community.dart';
import 'package:buid_arch/widgets/community_post_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows Author tag on the current member post', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: _postCard(currentProfileId: 7, authorId: 7),
        ),
      ),
    );

    expect(find.text('Author'), findsOneWidget);
  });

  testWidgets('does not show Author tag on another member post',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: _postCard(currentProfileId: 7, authorId: 9),
        ),
      ),
    );

    expect(find.text('Author'), findsNothing);
  });
}

CommunityPostCard _postCard({
  required int currentProfileId,
  required int authorId,
}) {
  final author = CommunityProfile(
    id: authorId,
    userId: authorId,
    displayName: 'Community Member',
    profession: 'Designer',
    professionType: 'Designer',
    postsCount: 1,
  );
  return CommunityPostCard(
    post: CommunityPost(
      id: 1,
      content: 'A community post',
      likesCount: 0,
      commentsCount: 0,
      likedByMe: false,
      createdAt: null,
      author: author,
    ),
    currentProfileId: currentProfileId,
    onLike: () {},
    onComments: () {},
    onAuthor: () {},
    onReport: () {},
    onDelete: () {},
  );
}
