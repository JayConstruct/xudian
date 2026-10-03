class ModuleInstallProvenance {
  const ModuleInstallProvenance({
    this.origin = 'local',
    this.publisherId,
    this.packageDigest,
    this.reviewId,
    this.signatureKeyId,
  });

  const ModuleInstallProvenance.ai()
      : origin = 'ai',
        publisherId = null,
        packageDigest = null,
        reviewId = null,
        signatureKeyId = null;

  final String origin;
  final String? publisherId;
  final String? packageDigest;
  final String? reviewId;
  final String? signatureKeyId;
}
