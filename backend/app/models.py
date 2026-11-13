"""Pydantic schemas. Field names follow docs/api-contract.md exactly."""
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field


class Patient(BaseModel):
    name: str
    age: int
    appearance: str
    personality: str


class Zone(BaseModel):
    id: str
    label: str
    attach_to: str
    offset: list[float]
    radius: float


class DialogueLine(BaseModel):
    id: str
    learner: str
    patient: str


class InvestigationInfo(BaseModel):
    id: str
    label: str


class CasePublic(BaseModel):
    case_id: str
    title: str
    learner_brief: str
    patient: Patient
    voice_context: str
    zones: list[Zone]
    scripted_dialogue: list[DialogueLine]
    investigations: list[InvestigationInfo] = []


class Health(BaseModel):
    status: str
    version: str
    cases: int


class SessionCreate(BaseModel):
    case_id: str


class SessionInfo(BaseModel):
    session_id: str
    started_at: str
    case: CasePublic


class ExamineRequest(BaseModel):
    body_part: str
    action: str = "palpation"


class ExamineResult(BaseModel):
    body_part: str
    action: str
    finding: str
    pain_level: int = Field(ge=0, le=10)
    reaction: Literal["strong_pain", "mild_pain", "no_pain"]
    patient_response: str
    animation: Literal["arm_withdrawal", "flinch", "none"]
    voice_context: str
    repeat_count: int


class InvestigationRequest(BaseModel):
    investigation_id: str


class InvestigationResult(BaseModel):
    investigation_id: str
    label: str
    modality: str
    title: str
    report: str
    impression: str
    image: str | None  # bundled image name in the app, or null: report only
    image_credit: str
    ordered_at: str
    repeat_count: int


class InteractionRequest(BaseModel):
    role: Literal["learner", "patient"]
    text: str
    timestamp: datetime | None = None


class InteractionCount(BaseModel):
    count: int


class Notes(BaseModel):
    """The learner's notebook. Compared with the session record; never a source of points."""
    history: str = ""
    examination: str = ""
    assessment: str = ""
    interpretation: str = ""  # what the investigation results mean
    management: str = ""      # immediate management
    follow_up: str = ""       # further imaging / follow-up plan


class DiagnoseRequest(BaseModel):
    diagnosis: str = Field(min_length=1)
    notes: Notes | None = None


class DocumentationItem(BaseModel):
    criterion_id: str
    label: str
    status: Literal["documented", "undocumented", "unsupported"]
    comment: str


class DiagnosticAssessment(BaseModel):
    verdict: Literal["correct", "partial", "incorrect", "not_submitted"]
    explanation: str
    expected: str | None


class CriterionResult(BaseModel):
    id: str
    label: str
    met: bool
    points: int
    max_points: int
    method: Literal["keyword", "rule"]
    evidence: str | None
    comment: str
    area: str | None = None  # management criteria only: investigation | interpretation | management | safety


class CategoryResult(BaseModel):
    id: str
    title: str
    score: int
    max_score: int
    criteria: list[CriterionResult]


class ManagementAssessment(BaseModel):
    """Investigation and management: scored separately, not part of total_score."""
    title: str
    score: int
    max_score: int
    criteria: list[CriterionResult]


class Feedback(BaseModel):
    session_id: str
    case_id: str
    diagnosis_submitted: str | None
    total_score: int
    max_score: int
    summary: str
    transcript_available: bool
    diagnostic_assessment: DiagnosticAssessment
    categories: list[CategoryResult]
    strengths: list[str]
    missed: list[str]
    relevant_findings: list[str]
    next_steps: list[str]
    documentation: list[DocumentationItem]
    management: ManagementAssessment
    investigations: list[str]
    disclaimer: str


class TokenResponse(BaseModel):
    token: str
