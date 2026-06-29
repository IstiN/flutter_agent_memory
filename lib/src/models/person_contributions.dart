/// Aggregated contributions for a single person.
class PersonContributions {
  final List<ContributionItem> questions;
  final List<ContributionItem> answers;
  final List<ContributionItem> notes;
  final List<TopicContribution> topics;

  PersonContributions({
    List<ContributionItem>? questions,
    List<ContributionItem>? answers,
    List<ContributionItem>? notes,
    List<TopicContribution>? topics,
  })  : questions = questions ?? <ContributionItem>[],
        answers = answers ?? <ContributionItem>[],
        notes = notes ?? <ContributionItem>[],
        topics = topics ?? <TopicContribution>[];
}

class ContributionItem {
  final String id;
  final String topic;
  final String date;

  const ContributionItem({required this.id, required this.topic, required this.date});
}

class TopicContribution {
  final String topicId;
  final int count;

  const TopicContribution({required this.topicId, required this.count});
}
