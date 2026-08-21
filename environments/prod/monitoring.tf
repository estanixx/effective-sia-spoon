# Ops-only channel, separate from the seat-notification path (which stays
# SES-only) -- SNS's plain-text email protocol is exactly what a "something
# broke" alert needs, and this does not reopen the "no SNS in the delivery
# path" design decision. One manual subscription-confirmation click for one
# ops address.

resource "aws_sns_topic" "ops_alerts" {
  name = "${var.name_prefix}-ops-alerts"
}

resource "aws_sns_topic_subscription" "ops_alerts_email" {
  topic_arn = aws_sns_topic.ops_alerts.arn
  protocol  = "email"
  endpoint  = var.ops_email
}

# Built-in, first-party, needs no code and no log string-matching --
# structurally the cheapest signal for crashes/timeouts/OOM/image-pull
# failures (design.md "Error policy and ops alerting").
resource "aws_cloudwatch_metric_alarm" "watcher_errors" {
  alarm_name          = "${var.name_prefix}-watcher-errors"
  alarm_description   = "course-seat-watcher Lambda reported >=1 error in a 10-minute window."
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = module.watcher.function_name }
  statistic           = "Sum"
  period              = 600
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.ops_alerts.arn]
  ok_actions          = [aws_sns_topic.ops_alerts.arn]
}

# The Errors alarm above structurally cannot see a successful-but-empty run
# (SIA label change, empty result table) or the schedule going silent
# entirely -- CoursesScraped is emitted every invocation regardless of
# outcome (metrics.py), so treat_missing_data = breaching over 3 consecutive
# 10-minute periods is the only mechanism in this design that catches total
# silence (design.md "Error policy and ops alerting").
resource "aws_cloudwatch_metric_alarm" "watcher_no_results" {
  alarm_name          = "${var.name_prefix}-watcher-no-results"
  alarm_description   = "course-seat-watcher scraped zero courses across 3 consecutive 10-minute windows, or the schedule stopped firing entirely."
  namespace           = "SiaSeatWatcher"
  metric_name         = "CoursesScraped"
  statistic           = "Sum"
  period              = 600
  evaluation_periods  = 3
  datapoints_to_alarm = 3
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = [aws_sns_topic.ops_alerts.arn]
  ok_actions          = [aws_sns_topic.ops_alerts.arn]
}
