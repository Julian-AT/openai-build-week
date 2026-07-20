export const PROPOSAL_MODEL = "gpt-5.6";

export type ProposalOutputSchema = Record<string, unknown>;

export interface ModelProposalInput {
  prompt: string;
  image_data_url?: string;
}

export interface ModelProposalResult {
  responseID: string;
  output: unknown;
}

export interface ProposalModelClient {
  generate(input: ModelProposalInput, signal: AbortSignal): Promise<ModelProposalResult>;
}

export interface ProposalGenerationRequest {
  model: typeof PROPOSAL_MODEL;
  prompt: string;
  imageDataURL?: string;
  instructions: string;
  outputSchema: ProposalOutputSchema;
  maxOutputTokens: 800;
  store: false;
}

export interface ProposalGenerator {
  generate(request: ProposalGenerationRequest, signal: AbortSignal): Promise<ModelProposalResult>;
}
