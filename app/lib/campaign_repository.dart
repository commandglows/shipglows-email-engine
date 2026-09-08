import 'dart:async';
import 'dart:convert';

import 'package:newsletter_studio_flutter/newsletter_studio_flutter.dart';

import 'central_email_api.dart';

class EmailBusiness {
  EmailBusiness(Map<String, dynamic> json)
    : id = json['id'] as String,
      brand = json['brand'] as String,
      from = json['from'] as String,
      audiences = (json['audiences'] as List).cast<Map<String, dynamic>>(),
      canTest = (json['capabilities'] as Map)['can_test'] == true,
      canApprove = (json['capabilities'] as Map)['can_approve'] == true,
      disabledReason =
          (json['capabilities'] as Map)['disabled_reason'] as String?,
      testRecipients = ((json['test_recipients'] as List?) ?? [])
          .cast<String>();

  final String id, brand, from;
  final List<Map<String, dynamic>> audiences;
  final bool canTest, canApprove;
  final String? disabledReason;
  final List<String> testRecipients;
}

NewsletterCampaign campaignFromJson(Map<String, dynamic> json) {
  final counters = (json['counters'] as Map?) ?? {};
  final status = NewsletterCampaignStatus.values.where(
    (s) => s.name == json['state'],
  );
  return NewsletterCampaign(
    id: json['id'] as String,
    title: json['title'] as String,
    subject: json['subject'] as String,
    revision: json['version'] as int,
    status: json['state'] == 'completed'
        ? _completedStatus(counters)
        : status.isEmpty
        ? NewsletterCampaignStatus.unknown
        : status.first,
    updatedAt: DateTime.parse(json['updated_at'] as String),
    scheduledAt: json['scheduled_at'] == null
        ? null
        : DateTime.parse(json['scheduled_at'] as String),
    audienceLabel: json['audience_id'] as String,
    eligibleCount:
        (json['eligible_count'] as num?)?.toInt() ??
        counters.values.whereType<num>().fold<int>(
          0,
          (sum, n) => sum + n.toInt(),
        ),
    submittedCount: (counters['submitted'] as num?)?.toInt() ?? 0,
    deliveredCount: (counters['delivered'] as num?)?.toInt() ?? 0,
    failedCount: (counters['failed'] as num?)?.toInt() ?? 0,
    unknownCount: (counters['unknown'] as num?)?.toInt() ?? 0,
  );
}

NewsletterCampaignStatus _completedStatus(Map counters) {
  int count(String key) => (counters[key] as num?)?.toInt() ?? 0;
  if (count('unknown') > 0) return NewsletterCampaignStatus.unknown;
  if (count('failed') > 0) {
    return count('delivered') > 0 || count('submitted') > 0
        ? NewsletterCampaignStatus.partiallyDelivered
        : NewsletterCampaignStatus.failed;
  }
  if (count('submitted') > 0) return NewsletterCampaignStatus.submitted;
  if (count('delivered') > 0) return NewsletterCampaignStatus.delivered;
  return NewsletterCampaignStatus.completed;
}

class CentralCampaignRepository implements NewsletterCampaignRepository {
  CentralCampaignRepository(this.api, this.business);
  final CentralEmailApi api;
  final EmailBusiness business;

  @override
  Future<NewsletterCampaignPage> list({
    String? cursor,
    NewsletterCampaignStatus? status,
    int limit = 25,
  }) async {
    final json = await api.get('campaigns', {
      'business_id': business.id,
      'cursor': ?cursor,
      if (status != null) 'state': status.name,
      'limit': limit.clamp(1, 25).toString(),
    });
    return NewsletterCampaignPage(
      items: (json['campaigns'] as List)
          .map((v) => campaignFromJson(v as Map<String, dynamic>))
          .toList(),
      nextCursor: json['next_cursor'] as String?,
    );
  }

  @override
  Future<NewsletterCampaign> create({required String title}) async {
    if (business.audiences.isEmpty) {
      throw const EmailApiException('configuration_unavailable');
    }
    final json = await api.post('campaigns', {
      'business_id': business.id,
      'title': title,
      'audience_id': business.audiences.first['id'],
      'locale': 'fr',
      'subject': '',
      'preheader': '',
      'blocks': <Object>[],
    });
    return campaignFromJson(json['campaign'] as Map<String, dynamic>);
  }

  Future<CampaignEditorSession> open(String id) async {
    final json = await api.get('campaigns/$id', {'business_id': business.id});
    return CampaignEditorSession(
      api,
      business,
      json['campaign'] as Map<String, dynamic>,
      rendered: json['rendered'] as Map<String, dynamic>?,
    );
  }
}

/// Owns server revision independently from optimistic keystroke revisions.
class CampaignEditorSession {
  CampaignEditorSession(this.api, this.business, this.record, {this.rendered});
  final CentralEmailApi api;
  final EmailBusiness business;
  Map<String, dynamic> record;
  Map<String, dynamic>? review;
  Map<String, dynamic>? rendered;
  String get id => record['id'] as String;
  int get version => record['version'] as int;
  String get state => record['state'] as String;
  String get audienceId => record['audience_id'] as String;
  String? _savedSignature;
  Future<void> _writes = Future.value();

  Future<T> _serial<T>(Future<T> Function() work) {
    final result = _writes.then((_) => work());
    _writes = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  NewsletterDraft get draft => NewsletterDraft(
    id: id,
    revision: version,
    title: record['title'] as String,
    subject: record['subject'] as String,
    preheader: record['preheader'] as String,
    blocks: (record['blocks'] as List).map((raw) {
      final b = raw as Map<String, dynamic>;
      final type = NewsletterBlockType.values.byName(b['type'] as String);
      return NewsletterBlock(
        id: b['id'] as String,
        type: type,
        text: b['text'] as String? ?? '',
        label: type == NewsletterBlockType.button ? b['text'] as String? : null,
        url: b['url'] == null ? null : Uri.tryParse(b['url'] as String),
        sourceId: b['source_id'] as String?,
      );
    }).toList(),
    sources: const [],
    status: state == 'draft'
        ? NewsletterDraftStatus.draft
        : state == 'scheduled'
        ? NewsletterDraftStatus.scheduled
        : NewsletterDraftStatus.sent,
  );

  Map<String, dynamic> _content(NewsletterDraft draft) => {
    'title': draft.title,
    'subject': draft.subject,
    'preheader': draft.preheader,
    'audience_id': audienceId,
    'locale': record['locale'],
    'blocks': draft.blocks
        .map(
          (b) => {
            'id': b.id,
            'type': b.type.name,
            'text': b.type == NewsletterBlockType.button
                ? b.label ?? b.text
                : b.text,
            if (b.url != null) 'url': b.url.toString(),
            if (b.sourceId != null) 'source_id': b.sourceId,
          },
        )
        .toList(),
  };

  Future<Map<String, dynamic>> command(
    String action, [
    Map<String, dynamic> extra = const {},
  ]) async {
    final result = await api.post('campaigns/$id/$action', {
      'business_id': business.id,
      'expected_version': version,
      ...extra,
    });
    if (result['campaign'] is Map<String, dynamic>) {
      record = result['campaign'] as Map<String, dynamic>;
    }
    return result;
  }

  Future<NewsletterDraft> save(NewsletterDraft value) => _serial(() async {
    final content = _content(value);
    final signature = jsonEncode(content);
    if (signature != _savedSignature) {
      await command('save', content);
      _savedSignature = signature;
      review = null;
    }
    return value.copyWith(saveState: NewsletterSaveState.saved);
  });

  Future<void> selectAudience(String audience, NewsletterDraft value) =>
      _serial(() async {
        if (!business.audiences.any((a) => a['id'] == audience)) {
          throw const EmailApiException('invalid_input');
        }
        final result = await command('save', {
          ..._content(value),
          'audience_id': audience,
        });
        record = result['campaign'] as Map<String, dynamic>;
        _savedSignature = jsonEncode(_content(value));
        review = null;
      });

  Future<NewsletterAudienceSummary> resolve(NewsletterDraft value) async {
    await save(value);
    // Progress bounded server pages without monopolizing the UI. A larger list
    // remains resumable through Refresh, with no fabricated exact total.
    for (var page = 0; page < 10; page++) {
      final result = await command('review');
      review = result['review'] as Map<String, dynamic>;
      if (review!['complete'] == true) break;
    }
    final complete = review!['complete'] == true;
    return NewsletterAudienceSummary(
      id: audienceId,
      label: complete ? audienceId : '$audienceId · estimation partielle',
      eligibleCount: review!['eligible_count'] as int,
      isResolved: complete,
    );
  }

  Future<NewsletterPreview> preview(
    NewsletterDraft value,
    NewsletterPreviewViewport viewport,
  ) async {
    if (state == 'draft') {
      await resolve(value);
    } else if (rendered == null) {
      final json = await api.get('campaigns/$id', {'business_id': business.id});
      rendered = json['rendered'] as Map<String, dynamic>?;
    }
    final content = state == 'draft' ? review : rendered;
    if (content == null) {
      throw const EmailApiException('invalid_backend_receipt');
    }
    return NewsletterPreview(
      revision: value.revision,
      viewport: viewport,
      subject: value.subject,
      preheader: value.preheader,
      plainText: content['text'] as String,
    );
  }

  Future<NewsletterTestReceipt> test(
    NewsletterDraft value,
    String recipient,
  ) async {
    await save(value);
    final result = await command('test', {'recipient': recipient});
    final receipt = result['test'] as Map<String, dynamic>;
    return NewsletterTestReceipt(
      operationId: receipt['message_id'] as String,
      draftRevision: value.revision,
      message: 'Email test placé dans la file. Sa réception reste à vérifier.',
      recipientLabel: recipient,
      sentAt: DateTime.now(),
    );
  }

  Future<NewsletterOperationReceipt> approve(
    NewsletterDraft value, [
    NewsletterSchedule? schedule,
  ]) async {
    await save(value);
    if (review == null || review!['version'] != version) {
      throw const EmailApiException('review_required');
    }
    await command('approve', {
      'review_id': review!['id'],
      if (schedule != null)
        'scheduled_at': schedule.sendAt.toUtc().toIso8601String(),
    });
    return NewsletterOperationReceipt(
      operationId: id,
      draftRevision: value.revision,
      message: schedule == null
          ? 'Campagne mise en file. Les livraisons apparaîtront dans le suivi.'
          : 'Campagne programmée.',
    );
  }

  Future<void> cancel() async {
    await command('cancel');
  }

  Future<NewsletterDeliveryStatus> delivery() async {
    final json = await api.get('campaigns/$id', {'business_id': business.id});
    record = json['campaign'] as Map<String, dynamic>;
    rendered = json['rendered'] as Map<String, dynamic>?;
    final counters = record['counters'] as Map;
    return NewsletterDeliveryStatus(
      state: switch (state) {
        'draft' => NewsletterDeliveryState.draft,
        'scheduled' => NewsletterDeliveryState.scheduled,
        'cancelled' => NewsletterDeliveryState.cancelled,
        'delivered' => NewsletterDeliveryState.delivered,
        'failed' => NewsletterDeliveryState.failed,
        'completed' => switch (_completedStatus(counters)) {
          NewsletterCampaignStatus.delivered =>
            NewsletterDeliveryState.delivered,
          NewsletterCampaignStatus.submitted =>
            NewsletterDeliveryState.submitted,
          NewsletterCampaignStatus.failed => NewsletterDeliveryState.failed,
          NewsletterCampaignStatus.unknown => NewsletterDeliveryState.unknown,
          NewsletterCampaignStatus.partiallyDelivered =>
            NewsletterDeliveryState.partiallyDelivered,
          _ => NewsletterDeliveryState.completed,
        },
        _ => NewsletterDeliveryState.sending,
      },
      message:
          '${counters['submitted'] ?? 0} acceptés · ${counters['delivered'] ?? 0} livrés · ${counters['failed'] ?? 0} échecs · ${counters['unknown'] ?? 0} résultats incertains',
      updatedAt: DateTime.parse(record['updated_at'] as String),
      operationId: id,
    );
  }
}
